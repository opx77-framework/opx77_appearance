---@meta

OpxAppearance.Presence = {}

--- One presence pass: asks for everybody else's look, then publishes this player's look when it
--- changed or went unanswered.
function OpxAppearance.Presence.Check() end

--- Starts over for a new world: the look is published and everybody's asked for again.
function OpxAppearance.Presence.Renew() end

--- Withdraws this player's body from observers until the next publication.
function OpxAppearance.Presence.Withdraw() end
