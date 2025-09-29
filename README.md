# StoryTree Core

This project serves as a part of a larger project to create a game engine from scratch. However, I strive to keep this library abstracted from the game engine and more generic. The initial focus of features may be around getting a minimal product for the engine, but I plan to expand the library to be generic and easy to use for any purpose.

Any tips, PRs, and overall help are more than welcome.

> ⚠️ Warn: This repo is currently exploratory and the API is subject to change with every merge into the main branch
> To help with the volatile nature, this project will be split into a develop and a main branch.

## Goal

A native windowing library cross-compiling without any fuss or problems to Windows, Linux (X11 + Wayland), MacOS, iOS, and Android. Supported platforms will include Windows, Linux (X11 + Wayland), MacOS; and will be expanded to Web, IOS, and Android in the future.

The library is written in as much pure Zig as possible to provide an easy to use API with minimal dependencies. There is nothing wrong with using GLFW and other related libraries, I just want to try to create something new. This library will start off basic and naïve and grow to be intuitive, easy to use, and full of platform specific opt in features.

Hopefully this library will remain generic enough to be able to be used with most other libraries and projects like `Vulkan` and `ImGUI`.

## Requirements

- **Linux**
  - Packages: `wayland-protocols`, `libwayland-dev` (or a varant that provides wayland-scanner), `libxkbcommon-dev`, `libdbus-1-dev`

## TODO

- [ ] Move dialog module to individual repo
- [ ] Move notification module to individual repo

- [-] Windows
  - [x] Basic window creation
    - [x] Blank Window
    - [x] Size
    - [x] Pos
    - [x] Icon
    - [x] Cursor
    - [x] Title
    - [x] Resizable
    - [x] Theme
    - [x] Show (min/max/normal)
  - [x] Window manipulation
    - [x] Minimize
    - [x] Maxamize
    - [x] Restore 
    - [x] Update Title
    - [x] Update Icon
    - [x] Update Cursor
    - [x] Show/Hide Cursor
    - [x] Set Cursor Pos
    - [x] Change Window Theme
    - [x] Set Cursor Capture
    - [x] Set and Update Menu
    - [x] Fullscreen
  - [-] Event listening and handling
    - [x] Close 
    - [-] Keyboard
      - [ ] Finish keyboard input to support dead keys
    - [x] Mouse
    - [x] Resize
    - [x] Menu
    - [ ] Repaint
    - [x] Theme Change
    - [x] Drag Drop
  - [-] Query
    - [x] Keys
    - [x] Mouse
    - [ ] Gamepad
  - [x] System Tray
  - [x] Menu
  - [x] Set App ID
  - [ ] Start Menu shortcut for things like associating notifications

- [ ] Wayland
  - [-] Basic window creation
    - [x] Blank Window
    - [x] Size
    - [x] Pos (Not Possible)
    - [ ] Icon
    - [ ] Cursor
    - [x] Title
    - [x] Resizable
        - Controlled by the rendering impl
    - [ ] Theme
    - [x] Show (min/max/normal)
        - Hidding is controlled by the rendering impl
  - [ ] Window manipulation
    - [x] Minimize
    - [x] Maxamize
    - [x] Restore 
    - [x] Update Title
    - [ ] Update Icon
    - [ ] Update Cursor
    - [ ] Show/Hide Cursor
    - [ ] Set Cursor Pos
    - [ ] Change Window Theme
    - [ ] Set Cursor Capture
    - [ ] Set and Update Menu
    - [x] Fullscreen
  - [ ] Event listening and handling
    - [x] Close 
    - [x] Keyboard
    - [x] Mouse
    - [x] Resize
    - [ ] Menu 
    - [ ] Repaint
    - [ ] Theme Change
    - [ ] Drag Drop
  - [ ] Query
    - [ ] Keys
    - [ ] Mouse
    - [ ] Gamepad, controller, joystick, etc.
  - [ ] System Tray
  - [ ] Custom Context Menu
  - [ ] Title Bar
  - [x] Set App ID
  - [ ] Menu

- [ ] MacOS
  - [ ] Basic window creation
    - [ ] Size
    - [ ] Pos
    - [ ] Icon
    - [ ] Cursor
    - [ ] Title
    - [ ] Resizable
    - [ ] Theme
    - [ ] Show (min/max/normal)
  - [ ] Window manipulation
    - [ ] Minimize
    - [ ] Maxamize
    - [ ] Restore 
    - [ ] Update Title
    - [ ] Update Icon
    - [ ] Update Cursor
    - [ ] Show/Hide Cursor
    - [ ] Set Cursor Pos
    - [ ] Change Window Theme
    - [ ] Set Cursor Capture
    - [ ] Set and Update Menu
    - [ ] Fullscreen
  - [ ] Event listening and handling
    - [ ] Close 
    - [ ] Keyboard
    - [ ] Mouse
    - [ ] Resize
    - [ ] Menu 
    - [ ] Repaint
    - [ ] Theme Change
    - [ ] Drag Drop
  - [ ] Query
    - [ ] Keys
    - [ ] Mouse
    - [ ] Gamepad, controller, joystick, etc.
  - [ ] System Tray
  - [ ] Custom Context Menu
  - [ ] Title Bar
  - [ ] Set App ID
  - [ ] Menu

## References

- GLFW \(C\): https://www.glfw.org/docs/3.3/window_guide.html
- Winit (Rust): https://github.com/rust-windowing/winit
  - [windows::window](https://github.com/rust-windowing/winit/blob/4cd6877e8e19e7e1ba957a409394dca1af4afcdd/src/platform_impl/windows/window.rs#L432)
- windows-rs (Rust): https://github.com/microsoft/windows-rs

- CursorOption \(Rust\): https://docs.rs/cursor-icon/latest/cursor_icon/

- Notifications
  - Windows
    - Toast Notification in plain C: https://gist.github.com/valinet/3283c79ba35fc8f103c747c8adbb6b23
    - Win32 ToastNotificationManager: https://learn.microsoft.com/en-us/uwp/api/windows.ui.notifications.toastnotificationmanager?view=winrt-26100

- Gamepad Specification:
  - W3C Gamepad API: https://www.w3.org/TR/gamepad/
  - There is no standard for game engines but mimicking the one for web browsers makes sense
