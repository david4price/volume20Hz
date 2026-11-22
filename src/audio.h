#import <Foundation/Foundation.h>

NSDictionary<NSString *, NSString *> *audio_output_devices(void);
NSString *audio_output_name(void);
void audio_select_output(NSString *uid);
void audio_observe_route_changes(dispatch_block_t handler);
void audio_remove_route_observer(void);
int start_audio(void);
void stop_audio(void);
