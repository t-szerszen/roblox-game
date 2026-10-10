# Pepper spray and scooter customization

These systems are synchronized from Roblox Studio into the Rojo source tree.
The server owns spray validation, effect timing and scooter customization
permissions. Clients only send input and render the approved state.

Remote instances are declared under ReplicatedStorage/Remotes. Shared
configuration and presentation helpers live under ReplicatedStorage/Shared.
