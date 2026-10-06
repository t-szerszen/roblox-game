# Studio Edit camera recovery

If WASD/Q/E still move the editor camera but holding the right mouse button no
longer rotates it, check `Workspace.CurrentCamera.CameraType`. On 2026-10-05 the
affected Studio session had `Scriptable`, with normal mouse sensitivity settings.
Restore `Fixed` for the Edit viewport through Camera properties or the Command
Bar:

```lua
assert(not game:GetService("RunService"):IsRunning(), "Stop Play first")
workspace.CurrentCamera.CameraType = Enum.CameraType.Fixed
```

Studio Assistant's `execute_luau` restores the previous camera type after a tool
call completes. Its Output warning confirms this restoration. When repairing
through that tool, apply the change in a one-shot delayed callback after its
cleanup, checking that Studio remains in Edit mode and the camera is unchanged.
Do not add a gameplay script or a persistent camera override for this editor
issue. Verify by holding the right mouse button and moving the mouse in the 3D
viewport; a successful property assignment alone does not verify mouse rotation.

Recovery was verified in the affected session: `Fixed` remained set after tool
cleanup, the camera look direction changed, and the user confirmed right-button
rotation worked again.
