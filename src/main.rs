use std::{
    f64::consts::TAU,
    time::{Duration, Instant},
};

#[cfg(not(test))]
unsafe extern "C" {
    fn run_app();
    fn start_audio() -> bool;
    fn stop_audio();
    fn show_state(state: i32);
}

const MAX_GAIN: f32 = 0.05;
const LOCK_LIMIT: Duration = Duration::from_secs(3600);

#[derive(Default)]
struct Tone {
    phase: f64,
    gain: f32,
    envelope: f64,
}

impl Tone {
    fn sample(&mut self, rate: f64, playing: bool) -> f32 {
        let sample = self.phase.sin() as f32 * self.gain;
        let duration = if playing { 12.5 } else { 25.0 };
        let direction = if playing { 1.0 } else { -1.0 };
        self.envelope = (self.envelope + direction / (rate * duration)).clamp(0.0, 1.0);
        // Snap within floating-point accumulation error of the endpoints.
        if self.envelope < 1e-9 {
            self.envelope = 0.0;
        } else if self.envelope > 1.0 - 1e-9 {
            self.envelope = 1.0;
        }
        self.gain = self.envelope as f32 * MAX_GAIN;
        self.phase = (self.phase + TAU * 20.0 / rate) % TAU;
        sample
    }
}

fn lock_expired(start: Option<Instant>, now: Instant, limit: Duration) -> bool {
    start.is_some_and(|time| now.saturating_duration_since(time) >= limit)
}

#[cfg(not(test))]
mod app {
    use super::*;
    use std::{
        cell::RefCell,
        sync::atomic::{AtomicBool, AtomicU32, Ordering::Relaxed},
    };

    static PLAY: AtomicBool = AtomicBool::new(false);
    static GAIN: AtomicU32 = AtomicU32::new(0);

    #[derive(Default)]
    struct Controller {
        stream: bool,
        unavailable: bool,
        locked: bool,
        locked_since: Option<Instant>,
    }

    thread_local! {
        static STATE: RefCell<Controller> = RefCell::default();
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
        for sample in buffer {
            *sample = tone.sample(rate, playing);
        }
        GAIN.store(tone.gain.to_bits(), Relaxed);
    }

    impl Controller {
        fn open(&mut self) {
            GAIN.store(0, Relaxed);
            self.stream = unsafe { start_audio() };
            self.unavailable = !self.stream;
            PLAY.store(self.stream, Relaxed);
        }

        fn close(&mut self) {
            unsafe { stop_audio() };
            self.stream = false;
            GAIN.store(0, Relaxed);
        }

        fn refresh(&mut self) {
            let playing = PLAY.load(Relaxed);
            let gain = f32::from_bits(GAIN.load(Relaxed));
            if self.stream && !playing && gain == 0.0 {
                self.close();
            }
            let status = match (self.unavailable, self.stream, playing) {
                (true, _, _) => 4,
                (_, false, _) => 0,
                (_, true, false) => 3,
                (_, true, true) if gain >= MAX_GAIN => 2,
                _ => 1,
            };
            unsafe { show_state(status) };
        }
    }

    #[unsafe(no_mangle)]
    extern "C" fn app_event(event: i32) {
        STATE.with_borrow_mut(|state| {
            let now = Instant::now();
            match event {
                0 => {
                    if state.locked && state.locked_since.is_none() {
                        state.locked_since = Some(now);
                    }
                    PLAY.store(true, Relaxed);
                    if !state.stream {
                        state.open();
                    }
                }
                1 => PLAY.store(false, Relaxed),
                2 if !state.locked => {
                    state.locked = true;
                    state.locked_since = Some(now);
                }
                3 => {
                    state.locked = false;
                    state.locked_since = None;
                }
                4 => {
                    state.locked_since = state.locked.then_some(now);
                }
                5 => {
                    let playing = PLAY.load(Relaxed);
                    if state.stream {
                        state.close();
                    }
                    if playing {
                        state.open();
                    }
                }
                6 => {
                    let limit = if cfg!(debug_assertions) {
                        std::env::var("VOLUME20HZ_LOCK_SECONDS")
                            .ok()
                            .and_then(|seconds| seconds.parse().ok())
                            .map_or(LOCK_LIMIT, Duration::from_secs)
                    } else {
                        LOCK_LIMIT
                    };
                    if lock_expired(state.locked_since, now, limit) {
                        state.locked_since = None;
                        PLAY.store(false, Relaxed);
                    }
                }
                7 => {
                    PLAY.store(false, Relaxed);
                    if state.stream {
                        state.close();
                    }
                }
                _ => {}
            }
            state.refresh();
        });
    }
}

#[cfg(not(test))]
fn main() {
    unsafe { run_app() };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tone_and_fade() {
        for rate in [44_100, 48_000] {
            let mut tone = Tone::default();
            for _ in 0..rate * 25 / 2 {
                tone.sample(rate as f64, true);
            }
            assert_eq!(tone.gain, MAX_GAIN);
            let samples: Vec<_> = (0..rate).map(|_| tone.sample(rate as f64, true)).collect();
            let cycles = samples
                .windows(2)
                .filter(|pair| pair[0] <= 0.0 && pair[1] > 0.0)
                .count();
            assert_eq!(cycles, 20);
            assert!(samples.iter().all(|sample| sample.abs() <= MAX_GAIN));
            tone.sample(rate as f64, false);
            let lower = tone.gain;
            tone.sample(rate as f64, true);
            assert!(tone.gain > lower);
            for _ in 0..rate * 25 {
                tone.sample(rate as f64, false);
            }
            assert_eq!(tone.gain, 0.0);
        }
    }

    #[test]
    fn only_expires_with_a_lock_at_the_deadline() {
        let start = Instant::now();
        let deadline = start + LOCK_LIMIT;
        assert!(!lock_expired(
            Some(start),
            deadline - Duration::from_secs(1),
            LOCK_LIMIT
        ));
        assert!(lock_expired(Some(start), deadline, LOCK_LIMIT));
        assert!(!lock_expired(None, deadline, LOCK_LIMIT));
        assert!(!lock_expired(Some(deadline), deadline, LOCK_LIMIT));
    }
}
