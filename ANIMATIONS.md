# Animation options for Gevun

These native options work with Gevun's iOS 27 target. Custom effects can be combined endlessly; this catalog covers the built-in families and practical patterns for this app. Availability and API names were checked against the installed iOS 27 SDK.

## Already present

Gevun uses system navigation push/back transitions, native sheet presentation/dismissal, menus and context menus, button press feedback, segmented controls, disclosure expansion, and loading indicators. Albums, Artists, Songs, Search, and Settings use separate native tabs, with Albums selected on startup. Navigation bars use iOS 27 native scroll minimization; the tab bar and its mini-player accessory use native scroll-down minimization. Soft scroll edges are enabled across the app. Album and artist detail pages use the artwork header’s own top shading and suppress the native top edge backdrop throughout scrolling, avoiding a backdrop switch on return to the top. Their navigation bars retain native minimization with [safe-area adjustment disabled](https://developer.apple.com/documentation/swiftui/toolbarminimizationsafeareaadjustment), so the full-bleed artwork viewport stays fixed as the controls move. Native soft effects remain at the other edges and on other pages. Cover-derived accents and player colors ease between tracks over 450 ms; main page backgrounds stay OLED black. The player opens with a spring from the bottom in a transparent window in the existing app scene, with a separate SwiftUI host. The main window keeps its native tab interface and mini-player mounted and live throughout the gesture. The mini-player retains the same artist and next-track layout, with implicit layout animations disabled. Dismissal removes the player window after the surface is hidden, without a screenshot-to-live handoff or view hierarchy restoration. A native UIKit pan recognizer on the player host handles downward pulls without relying on SwiftUI gesture routing or a scroll view. The presenter subscribes directly to expansion state to manage the player window’s lifetime. Ordinary downward pulls follow the finger in window coordinates; very long pulls add resistance. Its full surface scales slightly, gains a soft shadow, and progressively rounds its top corners. The resting player stays fixed on upward swipes; its artwork fits the available height. Release motion uses a display-link-driven critically damped spring, preserving momentum and allowing another pull to interrupt the return without a jump. Dismissal moves steadily off-screen and removes the player presentation once fully hidden; upward flicks return it even after a long pull. The player content does not scroll; lyrics and queue retain normal scrolling inside their sheets. App interruptions and rotation reset unfinished pulls. With Reduce Motion, theme colors change directly and the player uses short fades instead of movement. Timed lyrics follow with a short ease-out scroll unless Reduce Motion is enabled. There are no added symbol effects or looping decorative effects. Lyrics and Queue text buttons open normal native sheets with system presentation and drag dismissal.

Library, search, album, and artist pages keep the native status-bar tap gesture, but handle its [scroll-to-top delegate callback](https://developer.apple.com/documentation/uikit/uiscrollviewdelegate/scrollviewshouldscrolltotop(_:)) with a short display-link animation. Each frame sets the visible offset and lays out the scroll view so lazy content can render at intermediate positions. The bridge forwards other delegate messages to SwiftUI, respects delegate vetoes and Reduce Motion, and cancels on finger tracking, page removal, or app interruption. This workaround compiles but still needs device verification for the reported blank scrolling.

## Timing curves

An animation's timing is separate from what moves. Any of these curves can drive a fade, scale, position, color, or layout change.

| Curve | Feel | Use in Gevun |
| --- | --- | --- |
| `.default` | System default | Routine state changes |
| `.smooth` | Spring without bounce | Artwork changes, layout changes |
| `.snappy` | Spring with a little bounce | Filter selection, quick controls |
| `.bouncy` | Spring with more bounce | A small queue confirmation |
| `.spring(duration:bounce:)` | Tunable spring | Player expansion, custom controls |
| `.interactiveSpring` | Spring tuned for interaction | Drag release and snapping |
| `.interpolatingSpring` | Spring with explicit velocity/physics options | Gesture-driven motion |
| `.linear` | Constant speed | Progress or a custom rotating indicator |
| `.easeIn` | Starts slowly | An element leaving a screen |
| `.easeOut` | Settles gently | A new element appearing |
| `.easeInOut` | Gentle start and finish | Artwork cross-fades |
| `.timingCurve` | Custom Bézier/UnitCurve | A precise custom feel |
| `CustomAnimation` | Custom interpolation and velocity | Specialized motion that standard curves cannot express |

Animations can use delay, speed, repeat count, or repeat forever. For a calm interface, a suggested starting point is 150–250 ms for controls and fades, and 300–450 ms for larger movement. These durations are design suggestions, not system requirements. See Apple's [Animation reference](https://developer.apple.com/documentation/swiftui/animation) and [spring presets](https://developer.apple.com/documentation/swiftui/animation/snappy).

## View and content transitions

| Option | What it does | Suitable use |
| --- | --- | --- |
| Fade / opacity | Appears or disappears softly | Artwork loading, errors, empty states |
| Cross-fade | Replaces one view/image with another | Track artwork and titles |
| Scale | Grows or shrinks around an anchor | Press feedback, a queue confirmation |
| Move / slide / offset | Moves in or out from an edge or position | A compact notice, queue insertion |
| Push | Moves content out as new content arrives | Directional track changes |
| Blur replacement | Blurs between outgoing and incoming views | A restrained title change |
| Combined transition | Combines effects, such as fade + scale | Small confirmations |
| Asymmetric transition | Uses different entry and exit effects | Notices that enter and then fade away |
| Numeric text | Rolls changing digits | Queue counts; usually unnecessary for a ticking timer |
| Text interpolation | Interpolates supported text style changes | Selected headings or status text |
| Symbol replacement | Transitions between SF Symbol glyphs | Play ↔ pause, repeat ↔ repeat one |
| Custom `Transition` / animatable modifier | Defines a custom entry/exit effect | A specialized component |
| Identity / no animation | Changes instantly | Reduced Motion fallback, rapidly changing data |

Entry/exit transitions need insertion or removal of views. `contentTransition` instead changes content inside a stable view. A transition also needs a driving animation, such as `withAnimation` or `.animation(_:value:)`. See [SwiftUI animations](https://developer.apple.com/documentation/swiftui/animations) and [AnyTransition](https://developer.apple.com/documentation/swiftui/anytransition).

## Navigation and shared elements

| Option | Suitable use | Status |
| --- | --- | --- |
| Automatic push/back | Normal album, artist, playlist, and Settings navigation | Current |
| Separate scene window with its own SwiftUI host | Player expansion and continuous dismissal over the live library and mini-player, keeping their view hierarchy intact | Current |
| SwiftUI full-screen cover | Alternative presentation using `fullScreenCover` | Available |
| Native sheet presentation | Artist About, lyrics, queue, and connection editor | Current |
| Native tab-bar minimization | Shrinks tabs and the mini-player accessory while scrolling | Current |
| Native tab-bar search activation | The trailing search action activates the search field and keyboard; Cancel restores the previous tab | Current |
| Zoom navigation + `matchedTransitionSource` | Album artwork expands into its detail screen | Available |
| `.navigationTransition(.crossFade)` | A quieter screen change; added in iOS 27 | Available |
| `matchedGeometryEffect` | Moves/resizes shared elements within a coordinated view hierarchy | Available |
| Liquid Glass matched-geometry transition | Morphs coordinated custom glass controls using `GlassEffectContainer` and `glassEffectID` | Available |
| Liquid Glass materialize | Custom glass controls appear/disappear | Available |
| UIKit custom presentation | An interactive player expansion beyond standard SwiftUI presentations | Available with additional UIKit code |

`matchedGeometryEffect` is not a drop-in transition across unrelated sheets or navigation hierarchies. For artwork-to-detail navigation, use the dedicated zoom navigation API. See [NavigationTransition](https://developer.apple.com/documentation/swiftui/navigationtransition), [CrossFadeNavigationTransition](https://developer.apple.com/documentation/swiftui/crossfadenavigationtransition), and [custom Liquid Glass views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

## SF Symbol effects

These effects operate on SF Symbols, not arbitrary album artwork. Their appearance depends on the symbol's available layers and animation data. Use event-triggered effects for a tap and state-driven effects for a continuing state.

| Effect | Suitable use |
| --- | --- |
| Bounce | Add-to-queue confirmation |
| Pulse | A brief connection or buffering indication |
| Breathe | A subtle playing-state indicator |
| Wiggle | A one-time action hint or connection failure |
| Rotate | A refresh/retry indicator on an appropriate symbol |
| Variable color | Cycling layers on a waveform or connection symbol |
| Scale | Growing/shrinking a selected symbol |
| Appear | A status symbol arriving |
| Disappear | A status symbol leaving |
| Replace | Swapping play/pause or repeat glyphs |
| Magic replace | Morphing related supported glyphs, with replacement fallback |
| Draw on | Drawing a checkmark or supported status symbol |
| Draw off | Erasing a supported status symbol |

Where supported, effects offer whole-symbol or per-layer modes, direction, speed, repetition, and other effect-specific options. Automatic symbol transitions let the system choose the treatment. See Apple's [Symbols framework](https://developer.apple.com/documentation/symbols) and [DrawOnSymbolEffect](https://developer.apple.com/documentation/symbols/drawonsymboleffect).

## Scroll, gesture, and custom patterns

| Pattern | Native building blocks | Suitable use |
| --- | --- | --- |
| Native navigation-bar minimization | `toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)` | Current throughout Gevun; iOS 27 owns visibility and safe-area changes |
| Native soft scroll edges | `scrollEdgeEffectStyle(.soft, for: .all)` | Current throughout Gevun; system treatment where scrolling meets pinned content |
| Automatic pagination | `onScrollVisibilityChange` | Current in Albums, Songs, and Search; requests another page when the end is visible |
| Scroll-edge fade/scale | `scrollTransition` | Light treatment at shelf/viewport edges |
| Parallax | `visualEffect` + geometry | Artwork that moves less than surrounding content |
| Stretching artwork | `GeometryReader` in the native vertical scroll coordinate space, resizing and offsetting the artwork during layout | Current album and artist headers; a one-pixel overlap covers fractional top-edge gaps, and pull-down returns with native scroll bounce |
| Button press compression | A custom `ButtonStyle`, scale, opacity, spring | Tactile-feeling playback controls |
| Drag and snap | Native pan recognizer + display link + critically damped spring | Current player pull-down and interruptible return; gesture state + SwiftUI springs are also available for other interactions |
| Color / tint interpolation | Animated foreground/background colors | Current artwork-derived theme updates; also available for repeat states |
| Corner-radius / frame / position morph | Animated shape and layout properties | A custom mini-player expansion |
| Shape/path drawing | `Shape`, `trim`, `Animatable` | A custom progress ring |
| Progress interpolation | Animatable values or system `ProgressView` | Buffering, transfer progress if added later |
| Waveform / equalizer bars | `TimelineView`, `Canvas`, or phase animation | A playing-state decoration, not actual audio metering |
| One-time shake | `keyframeAnimator` or animatable offset | A failed connection submission |
| Staggered appearance | Per-item delay + transition | An occasional first library reveal |
| Multi-step motion | `phaseAnimator` | A brief confirmation sequence |
| Precisely choreographed motion | `keyframeAnimator`, linear/cubic/spring/move keyframes | Small branded feedback |
| Gradient / mesh animation | Animated gradient data, `MeshGradient`, `TimelineView` | A restrained player backdrop |
| Shimmer, ripple, distortion | Masks, Canvas, or SwiftUI shader effects | Specialized effects; more visual activity |
| Custom layer animation | UIKit/Core Animation: `CABasicAnimation`, `CAKeyframeAnimation`, `CASpringAnimation`, `CATransition` | Effects requiring direct layer control |

Apart from the rows marked current, these are optional implementation patterns. A decorative waveform is not a measurement of the streamed audio. See Apple's [animation sequencing guide](https://developer.apple.com/documentation/swiftui/controlling-the-timing-and-movements-of-your-animations).

## Suggested calm combination

1. Fade artwork in once it loads.
2. Use zoom for album-to-detail navigation.
3. Replace the play/pause glyph and give add-to-queue a small event-triggered bounce.
4. Use a short snappy selection change for filters.
5. Keep native sheets and navigation; preserve tab geometry during player gestures.

For custom motion, read `accessibilityReduceMotion`: skip zoom, parallax, shakes, large transforms, and repeating decoration when enabled, using an instant change or short fade instead. Keep effects tied to specific interactions rather than animating whole screens every time the playback timer updates.

Haptic feedback can accompany taps through `sensoryFeedback`; it is separate from visual animation. It is not enabled by this UI cleanup.
