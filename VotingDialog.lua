if Debug then Debug.beginFile "VotingDialog" end
OnInit.module("VotingDialog", function(require)
    require "MultiOptionDialog"

    --[[
    VotingDialog v1.1 by Insanity_AI
    ------------------------------------------------------------------------------
    MultiOptionDialog extension to wrap them in a player voting logic.

    Requires:
        Total Initialization - https://www.hiveworkshop.com/threads/total-initialization.317099/
        MultiOptionDialog - https://www.hiveworkshop.com/threads/lua-dialog-queue.346286/
        SetUtils - https://www.hiveworkshop.com/threads/setutils.353716/

    Installation:
        Just Plug & Play, nothing specific to be done.

    MultiOptionDialog API:
        VotingDialog.create(data?)      -> creates a new VotingDialog.
                                        -> data can be an existing VotingDialog object to make another copy of.
        VotingDialog.votingDoneCallback - callback function for when all players have comitted their votes.
        VotingDialog.title              - Title text for dialog. (nillable)
        VotingDialog.buttons            - array of MultiOptionDialogButton objects (not nillable, must be at least empty table.)
        VotingDialog.commitButton       - DialogButtonWrapper for commit.
                                        - commit button's callback is not to be used, as it is used by VotingDiaog to count votes!
        VotingDialog:Enqueue(playerSet) -> enqueues VotingDialog for Set of players.
        VotingDialog:Dequeue(playerSet) -> dequeues VotingDialog for Set of players.
        MultiOptionDialog.callback is not to be used by end-user, it is used by VotingDialog to count votes!
]]

    ---@class VotingDialog : MultiOptionDialog
    ---@field votingDoneCallback fun(selectedOptions: MultiOptionDialogButtonOption[])
    VotingDialog = {}
    VotingDialog.__index = VotingDialog
    setmetatable(VotingDialog, MultiOptionDialog)

    ---@param data? VotingDialog
    ---@return VotingDialog
    VotingDialog.create = function(data)
        local instance = setmetatable(MultiOptionDialog.create(data), VotingDialog)

        if data ~= nil then
            instance.votingDoneCallback = data.votingDoneCallback
        end

        return instance --[[@as VotingDialog]]
    end

    -- jesus christ this datastructure.
    local playersVotes = {} ---@type table<VotingDialog, {players : Set, buttonOptionCounts: table<MultiOptionDialogButton, table<MultiOptionDialogButtonOption, integer>>}>

    ---@param dialog VotingDialog
    local function functionVotingFinish(dialog)
        local selectedOptions = {} ---@type MultiOptionDialogButtonOption[]

        for _, optionCountPairs in pairs(playersVotes[dialog].buttonOptionCounts) do
            local maxOption = nil
            local max = nil
            for option, count in pairs(optionCountPairs) do
                if max == nil or max < count then
                    maxOption = option
                    max = count
                end
            end

            table.insert(selectedOptions, maxOption)
        end

        playersVotes[dialog] = nil
        dialog.votingDoneCallback(selectedOptions)
    end

    ---@param dialog VotingDialog
    ---@param player player
    ---@param buttonChosenOptionPairs table<MultiOptionDialogButton, MultiOptionDialogButtonOption>
    local function processPlayerCommit(dialog, player, buttonChosenOptionPairs)
        local dataStruct = playersVotes[dialog]
        dataStruct.players:removeSingle(player)

        for button, option in pairs(buttonChosenOptionPairs) do
            if dataStruct.buttonOptionCounts[button] == nil then
                dataStruct.buttonOptionCounts[button] = {}
                dataStruct.buttonOptionCounts[button][option] = 1
            else
                dataStruct.buttonOptionCounts[button][option] = dataStruct.buttonOptionCounts[button][option] + 1
            end
        end

        if dataStruct.players:isEmpty() then
            functionVotingFinish(dialog)
        end
    end

    ---@param players Set
    ---@return boolean success
    function VotingDialog:Enqueue(players)
        if playersVotes[self] ~= nil then
            -- Already queued up!
            return false
        end

        local dataStruct = { ---@type {players : Set, buttonOptionCounts: table<MultiOptionDialogButton, table<MultiOptionDialogButtonOption, integer>>}
            players = players,
            buttonOptionCounts = {}
        }

        playersVotes[self] = dataStruct

        self.callback = processPlayerCommit
        MultiOptionDialog.Enqueue(self, players)

        return true
    end

    ---@param players Set
    ---@return boolean success
    function VotingDialog:Dequeue(players)
        if playersVotes[self] == nil then
            -- Not queued up!
            return false
        end

        playersVotes[self].players = playersVotes[self].players:removeAll(players)
        if playersVotes[self].players:isEmpty() then
            functionVotingFinish(self)
        end

        MultiOptionDialog:Dequeue(players);
        return true
    end
end)
if Debug then Debug.endFile() end
