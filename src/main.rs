use std::{
    f64::consts::TAU,
    time::{Duration, Instant},
};

const MAX_GAIN: f32 = 0.05;
const DEFAULT_LOCK_LIMIT: Duration = Duration::from_secs(3600);
const RETRY_DELAY: Duration = Duration::from_secs(3);

#[derive(Default)]
struct Tone {
    phase: f64,
    envelope: f64,
    level: f32,
}

impl Tone {
    fn sample(&mut self, rate: f64, playing: bool, target: f32) -> f32 {
        // Smooth changes to the gain setting independently of the playback fade.
        let level_step = MAX_GAIN / (rate as f32 * 0.1);
        self.level += (target - self.level).clamp(-level_step, level_step);
        let sample = self.phase.sin() as f32 * self.envelope as f32 * self.level;

        let step = if playing { 1.0 / 12.5 } else { -1.0 / 25.0 };
        self.envelope = (self.envelope + step / rate).clamp(0.0, 1.0);
        // Snap within floating-point accumulation error of the endpoints.
        if self.envelope < 1e-9 {
            self.envelope = 0.0;
        } else if self.envelope > 1.0 - 1e-9 {
            self.envelope = 1.0;
        }
        self.phase = (self.phase + TAU * 20.0 / rate) % TAU;
        sample
    }
}

fn lock_expired(start: Option<Instant>, now: Instant, limit: Duration) -> bool {
    start.is_some_and(|time| now.saturating_duration_since(time) >= limit)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum StartResult {
    Started,
    MissingSoundbar,
    Unavailable,
}

// Values shared with the macOS presentation layer.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(i32)]
enum Status {
    Stopped = 0,
    FadingIn = 1,
    Playing = 2,
    FadingOut = 3,
    WaitingForSoundbar = 4,
    Unavailable = 5,
    StoppedAfterLock = 6,
    FadingOutAfterLock = 7,
}

#[derive(Clone, Copy)]
enum Event {
    Play,
    Stop,
    Lock,
    Unlock,
    Wake,
    RouteChanged,
    Tick,
    Quit,
}

trait Audio {
    fn start(&mut self) -> StartResult;
    fn stop(&mut self);
    fn set_playing(&mut self, playing: bool);
    fn envelope(&self) -> f32;
}

struct Controller {
    requested: bool,
    streaming: bool,
    last_start: StartResult,
    retry_at: Option<Instant>,
    locked: bool,
    locked_since: Option<Instant>,
    lock_limit: Duration,
    stopped_after_lock: bool,
}

impl Default for Controller {
    fn default() -> Self {
        Self {
            requested: false,
            streaming: false,
            last_start: StartResult::Unavailable,
            retry_at: None,
            locked: false,
            locked_since: None,
            lock_limit: DEFAULT_LOCK_LIMIT,
            stopped_after_lock: false,
        }
    }
}

impl Controller {
    fn cancel_playback(&mut self, audio: &mut impl Audio) {
        self.requested = false;
        self.retry_at = None;
        audio.set_playing(false);
    }

    fn close_stream(&mut self, audio: &mut impl Audio) {
        if self.streaming {
            audio.set_playing(false);
            audio.stop();
            self.streaming = false;
        }
    }

    fn handle(&mut self, event: Event, now: Instant, audio: &mut impl Audio) -> Status {
        match event {
            Event::Play => {
                self.requested = true;
                self.retry_at = None;
                self.stopped_after_lock = false;
                if self.locked {
                    self.locked_since.get_or_insert(now);
                }
            }
            Event::Stop => {
                self.stopped_after_lock = false;
                self.cancel_playback(audio);
            }
            Event::Lock if !self.locked => {
                self.locked = true;
                self.locked_since = Some(now);
            }
            Event::Unlock => {
                self.locked = false;
                self.locked_since = None;
            }
            Event::Wake => {
                self.locked_since = self.locked.then_some(now);
                self.close_stream(audio);
                self.retry_at = None;
            }
            Event::RouteChanged => {
                self.close_stream(audio);
                self.retry_at = None;
            }
            Event::Quit => {
                self.cancel_playback(audio);
                self.close_stream(audio);
            }
            Event::Lock | Event::Tick => {}
        }

        if lock_expired(self.locked_since, now, self.lock_limit) {
            self.locked_since = None;
            if self.requested {
                self.stopped_after_lock = true;
                self.cancel_playback(audio);
            }
        }

        if self.requested && !self.streaming && self.retry_at.is_none_or(|retry| now >= retry) {
            self.last_start = audio.start();
            self.streaming = self.last_start == StartResult::Started;
            self.retry_at = (!self.streaming).then_some(now + RETRY_DELAY);
        }
        if self.requested && self.streaming {
            audio.set_playing(true);
        }

        let envelope = audio.envelope();
        if self.streaming && !self.requested && envelope == 0.0 {
            self.close_stream(audio);
        }

        match (self.requested, self.streaming) {
            (true, true) if envelope == 1.0 => Status::Playing,
            (true, true) => Status::FadingIn,
            (true, false) if self.last_start == StartResult::MissingSoundbar => {
                Status::WaitingForSoundbar
            }
            (true, false) => Status::Unavailable,
            (false, true) if self.stopped_after_lock => Status::FadingOutAfterLock,
            (false, true) => Status::FadingOut,
            (false, false) if self.stopped_after_lock => Status::StoppedAfterLock,
            (false, false) => Status::Stopped,
        }
    }
}

#[cfg(not(test))]
mod app {
    use super::*;
    use std::{
        cell::RefCell,
        sync::atomic::{AtomicBool, AtomicU32, Ordering::Relaxed},
    };

    unsafe extern "C" {
        pub(super) fn run_app();
        fn start_audio() -> i32;
        fn stop_audio();
        fn show_state(state: i32, requested: bool);
    }

    static PLAY: AtomicBool = AtomicBool::new(false);
    static ENVELOPE: AtomicU32 = AtomicU32::new(0);
    static TARGET_GAIN: AtomicU32 = AtomicU32::new(MAX_GAIN.to_bits());

    thread_local! {
        static STATE: RefCell<Controller> = RefCell::default();
    }

    struct MacAudio;

    impl Audio for MacAudio {
        fn start(&mut self) -> StartResult {
            ENVELOPE.store(0, Relaxed);
            match unsafe { start_audio() } {
                0 => StartResult::Started,
                1 => StartResult::MissingSoundbar,
                _ => StartResult::Unavailable,
            }
        }

        fn stop(&mut self) {
            unsafe { stop_audio() };
            ENVELOPE.store(0, Relaxed);
        }

        fn set_playing(&mut self, playing: bool) {
            PLAY.store(playing, Relaxed);
        }

        fn envelope(&self) -> f32 {
            f32::from_bits(ENVELOPE.load(Relaxed))
        }
    }

    #[unsafe(no_mangle)]
    extern "C" fn tone_create() -> *mut Tone {
        Box::into_raw(Box::new(Tone::default()))
    }

    #[unsafe(no_mangle)]
    unsafe extern "C" fn tone_destroy(tone: *mut Tone) {
        drop(unsafe { Box::from_raw(tone) });
    }

    #[unsafe(no_mangle)]
    unsafe extern "C" fn tone_render(tone: *mut Tone, buffer: *mut f32, frames: usize, rate: f64) {
        let tone = unsafe { &mut *tone };
        let buffer = unsafe { std::slice::from_raw_parts_mut(buffer, frames) };
        let playing = PLAY.load(Relaxed);
        let target = f32::from_bits(TARGET_GAIN.load(Relaxed));
        for sample in buffer {
            *sample = tone.sample(rate, playing, target);
        }
        ENVELOPE.store((tone.envelope as f32).to_bits(), Relaxed);
    }

    #[unsafe(no_mangle)]
    extern "C" fn app_set_gain(percent: f32) {
        let target = (percent / 100.0).clamp(0.0, MAX_GAIN);
        TARGET_GAIN.store(target.to_bits(), Relaxed);
    }

    #[unsafe(no_mangle)]
    extern "C" fn app_set_lock_minutes(minutes: u32) {
        let configured = Duration::from_secs(u64::from(minutes) * 60);
        let limit = if cfg!(debug_assertions) {
            std::env::var("VOLUME20HZ_LOCK_SECONDS")
                .ok()
                .and_then(|value| value.parse().ok())
                .map_or(configured, Duration::from_secs)
        } else {
            configured
        };
        STATE.with_borrow_mut(|state| state.lock_limit = limit);
        app_event(6);
    }

    #[unsafe(no_mangle)]
    extern "C" fn app_event(event: i32) {
        let event = match event {
            0 => Event::Play,
            1 => Event::Stop,
            2 => Event::Lock,
            3 => Event::Unlock,
            4 => Event::Wake,
            5 => Event::RouteChanged,
            6 => Event::Tick,
            7 => Event::Quit,
            _ => return,
        };
        let (status, requested) = STATE.with_borrow_mut(|state| {
            let status = state.handle(event, Instant::now(), &mut MacAudio);
            (status, state.requested)
        });
        unsafe { show_state(status as i32, requested) };
    }
}

#[cfg(not(test))]
fn main() {
    unsafe { app::run_app() };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tone_and_fade() {
        for rate in [44_100, 48_000] {
            let mut tone = Tone::default();
            for _ in 0..rate * 25 / 2 {
                tone.sample(rate as f64, true, MAX_GAIN);
            }
            assert_eq!(tone.envelope, 1.0);
            let samples: Vec<_> = (0..rate)
                .map(|_| tone.sample(rate as f64, true, MAX_GAIN))
                .collect();
            let cycles = samples
                .windows(2)
                .filter(|pair| pair[0] <= 0.0 && pair[1] > 0.0)
                .count();
            assert_eq!(cycles, 20);
            assert!(samples.iter().all(|sample| sample.abs() <= MAX_GAIN));
            tone.sample(rate as f64, false, MAX_GAIN);
            let lower = tone.envelope;
            tone.sample(rate as f64, true, MAX_GAIN);
            assert!(tone.envelope > lower);
            for _ in 0..rate * 25 {
                tone.sample(rate as f64, false, MAX_GAIN);
            }
            assert_eq!(tone.envelope, 0.0);
        }
    }

    #[test]
    fn gain_changes_smoothly_while_playing() {
        let rate = 48_000.0;
        let mut tone = Tone {
            envelope: 1.0,
            level: MAX_GAIN,
            ..Tone::default()
        };
        let lower = 0.005;
        tone.sample(rate, true, lower);
        assert!(tone.level < MAX_GAIN && tone.level > lower);
        for _ in 0..4_800 {
            tone.sample(rate, true, lower);
        }
        assert_eq!(tone.level, lower);
        assert_eq!(tone.envelope, 1.0);
    }

    #[test]
    fn only_expires_with_a_lock_at_the_deadline() {
        let start = Instant::now();
        let deadline = start + DEFAULT_LOCK_LIMIT;
        assert!(!lock_expired(
            Some(start),
            deadline - Duration::from_secs(1),
            DEFAULT_LOCK_LIMIT
        ));
        assert!(lock_expired(Some(start), deadline, DEFAULT_LOCK_LIMIT));
        assert!(!lock_expired(None, deadline, DEFAULT_LOCK_LIMIT));
        assert!(!lock_expired(Some(deadline), deadline, DEFAULT_LOCK_LIMIT));
    }

    struct TestAudio {
        result: StartResult,
        starts: usize,
        stops: usize,
        playing: bool,
        envelope: f32,
    }

    impl TestAudio {
        fn new(result: StartResult) -> Self {
            Self {
                result,
                starts: 0,
                stops: 0,
                playing: false,
                envelope: 0.0,
            }
        }
    }

    impl Audio for TestAudio {
        fn start(&mut self) -> StartResult {
            self.starts += 1;
            self.result
        }

        fn stop(&mut self) {
            self.stops += 1;
            self.envelope = 0.0;
        }

        fn set_playing(&mut self, playing: bool) {
            self.playing = playing;
        }

        fn envelope(&self) -> f32 {
            self.envelope
        }
    }

    #[test]
    fn reconnects_after_device_disappears_and_a_restart_fails() {
        let now = Instant::now();
        let mut state = Controller::default();
        let mut audio = TestAudio::new(StartResult::Started);
        assert_eq!(state.handle(Event::Play, now, &mut audio), Status::FadingIn);
        audio.envelope = 1.0;
        assert_eq!(state.handle(Event::Tick, now, &mut audio), Status::Playing);

        audio.result = StartResult::MissingSoundbar;
        assert_eq!(
            state.handle(Event::RouteChanged, now, &mut audio),
            Status::WaitingForSoundbar
        );
        assert!(!audio.playing);
        assert_eq!(audio.stops, 1);

        audio.result = StartResult::Unavailable;
        assert_eq!(
            state.handle(Event::RouteChanged, now, &mut audio),
            Status::Unavailable
        );
        audio.result = StartResult::Started;
        assert_eq!(
            state.handle(Event::Tick, now, &mut audio),
            Status::Unavailable
        );
        assert_eq!(audio.starts, 3);
        assert_eq!(
            state.handle(Event::Tick, now + RETRY_DELAY, &mut audio),
            Status::FadingIn
        );
        assert!(audio.playing);
    }

    #[test]
    fn manual_stop_cancels_pending_playback() {
        let now = Instant::now();
        let mut state = Controller::default();
        let mut audio = TestAudio::new(StartResult::MissingSoundbar);
        state.handle(Event::Play, now, &mut audio);
        assert_eq!(state.handle(Event::Stop, now, &mut audio), Status::Stopped);
        audio.result = StartResult::Started;
        for event in [Event::RouteChanged, Event::Wake, Event::Tick] {
            assert_eq!(
                state.handle(event, now + RETRY_DELAY, &mut audio),
                Status::Stopped
            );
        }
        assert_eq!(audio.starts, 1);
        assert!(!audio.playing);
        assert_eq!(state.handle(Event::Quit, now, &mut audio), Status::Stopped);
    }

    #[test]
    fn lock_timeout_cancels_a_pending_reconnect_at_the_deadline() {
        let now = Instant::now();
        let limit = Duration::from_secs(15 * 60);
        let mut state = Controller {
            lock_limit: limit,
            ..Controller::default()
        };
        let mut audio = TestAudio::new(StartResult::MissingSoundbar);
        state.handle(Event::Play, now, &mut audio);
        state.handle(Event::Lock, now, &mut audio);
        audio.result = StartResult::Started;
        assert_eq!(
            state.handle(Event::RouteChanged, now + limit, &mut audio),
            Status::StoppedAfterLock
        );
        assert_eq!(
            state.handle(Event::Unlock, now + limit, &mut audio),
            Status::StoppedAfterLock
        );
        assert_eq!(audio.starts, 1);
        assert_eq!(
            state.handle(Event::Play, now + limit, &mut audio),
            Status::FadingIn
        );
    }

    #[test]
    fn lock_stop_keeps_the_reason_through_the_fade() {
        let mut state = Controller::default();
        let now = Instant::now();
        let mut audio = TestAudio::new(StartResult::Started);
        state.handle(Event::Play, now, &mut audio);
        state.handle(Event::Lock, now, &mut audio);
        audio.envelope = 1.0;
        let deadline = now + DEFAULT_LOCK_LIMIT;
        assert_eq!(
            state.handle(Event::Tick, deadline, &mut audio),
            Status::FadingOutAfterLock
        );
        assert!(!audio.playing);
        audio.envelope = 0.0;
        assert_eq!(
            state.handle(Event::Tick, deadline, &mut audio),
            Status::StoppedAfterLock
        );
        assert_eq!(audio.stops, 1);
    }
}
