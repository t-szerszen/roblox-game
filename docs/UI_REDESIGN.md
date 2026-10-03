# Shop and phone appearance

## Shop readability correction

The shop keeps dark mode with brighter slate surfaces for its window, product cards and preview areas. Its backdrop dims the world by 28%, and disabled purchase buttons use readable muted text on a distinct solid surface. Preview ambient light is increased independently of world lighting. These values live in Theme.Shop; the phone palette remains separate.

The original shop gradient was directly under CanvasGroup, which applies visual modifiers to its complete flattened contents, including labels and model previews. The gradient now belongs to a white background Frame behind the content, preserving text/preview colors. Backdrop, window and confirmation layers have explicit sibling ordering. See the [Roblox CanvasGroup documentation](https://create.roblox.com/docs/reference/engine/classes/CanvasGroup). Purchase availability, confirmation, pricing and server authority are unchanged.

Verification: Rojo build, Roblox-aware strict analysis and 133 CLI UI assertions passed. In a fresh Studio Play session, shop fixtures passed 26 client and 26 controller assertions. Runtime inspection confirmed the gradient is confined to the background, the open panel reaches zero group transparency, disabled status text remains fully opaque and preview lighting/surface colors use the new shop palette.

## Current product decision

The phone returns to its appearance from `e494b62` (`feat: polish phone app experience`): dark titanium body, navy-to-purple wallpaper, Dynamic Island and camera detail, clock/status bar, five colored gradient icons, TELEFON HUD with key badge, and the bottom home indicator. Application cards use the original dark surfaces and colored accent strips/actions. Optional app image IDs remain replaceable; unsupplied artwork leaves colored icons empty, as in the original.

This is a presentation change. The current controller, server remotes, permissions, ownership and gameplay rules remain intact. The phone retains responsive safe-area sizing, 44px action targets, keyboard/touch/gamepad navigation, serialized requests, notification coalescing, draft retention, input ownership, click audio, timed/dismissible toasts and resource cleanup. Current transition timing is retained. The phone's desktop footprint follows the responsive redesign rather than restoring the original fixed 260×540 aspect constraint.

## Module boundaries

- `Shared/Phone/PhoneTheme` holds the original phone palette independently of the shop theme.
- `PhoneComponents` styles shared button/label primitives while retaining their activation guards, controller focus and connection cleanup.
- `PhoneView` renders the body, screen, navigation and app icons; `PhoneAppsView` renders application cards. Decorations sit outside the card list to avoid changing automatic content measurement.
- `PhoneClient` remains the controller; this appearance change does not alter it. `Shared/UI`, shop views, server systems and the authored map are unchanged by this update.

## Verification

The Rojo build and Roblox-aware strict analysis passed. The CLI UI suite passed 133 assertions. In a fresh Studio Play session, phone fixtures passed 33 view, 30 controller and 7 typing/transport assertions, including draft retention, coalesced refreshes, ownership/leader restrictions, rapid transitions, responsive containment and movement-lock restoration. Runtime inspection confirmed the titanium color, wallpaper gradient, Dynamic Island, 56×56 gradient icons, home indicator and stable card heights.

The typing check installs a read-only mocked phone transport in a solo Studio Play server. Stop Play immediately after that fixture to restore normal transport; this was done during verification. The fixture does not grant profile entitlements and refuses gameplay mutations. Actual gamepad/touch input and final visual acceptance remain manual checks; programmatic layout inspection does not replace them.
