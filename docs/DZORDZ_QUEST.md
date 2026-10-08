# Dzordz quest

The Dzordz bag quest is authored in Studio and versioned through Rojo. Its
configuration is shared, the server owns quest state and pickup validation, and
the client only presents dialogue, input and progress UI.

The reusable bag asset lives under ReplicatedStorage/DzordzQuestAssets. The
server creates the Remotes/DzordzQuest/Action RemoteFunction at runtime and
validates proximity, cooldowns, tap count and pickup timing.
