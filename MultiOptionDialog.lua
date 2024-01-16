do
--[[
    MultiOptionDialog v1.0 by Insanity_AI
    ------------------------------------------------------------------------------
    DialogQueue extension to handle dialogs with buttons which cycle options and commit button at the end.
    Each option has a previewFunc which can be called when that option is currently selected.
    dialog's callback function is called when the player has commited their options.

    Requires:
        DialogQueue - [INSERT LINK HERE]
        SetUtils - https://www.hiveworkshop.com/threads/set-group-datastructure.331886/

    Installation:
        Just Plug & Play, nothing specific to be done.
        
    MultiOptionDialog API:
        MultiOptionDialog.create(data?) -> creates a new MultiOptionDialog.
                                        -> data can be an existing MultiOptionDialog object to make another copy of.
        MultiOptionDialog.callback      - callback function for when MultiOptionDialog has been commited.
        MultiOptionDialog.title         - Title text for dialog. (nillable)
        MultiOptionDialog.buttons       - array of MultiOptionDialogButton objects (not nillable, must be at least empty table.)
        MultiOptionDialog.commitButton  - DialogButtonWrapper for commit.
        MultiOptionDialog:Enqueue(playerSet) -> enqueues MultiOptionDialog for Set of players.
        MultiOptionDialog:Dequeue(playerSet) -> dequeues MultiOptionDialog for Set of players.
    
    MultiOptionDialogButton API: 
        MultiOptionDialogButton.create(data?)   -> data is an existing MultiOptionDialogButton object to make another copy of.
        MultiOptionDialogButton.messageFormat   - format string to merge button prefix and option name.
        MultiOptionDialogButton.hotkey          - button's hotkey (must be single char or nil)
        MultiOptionDialogButton.options         - array of MultiOptionDialogButtonOption to cycle through on button click. (not nillable, must be at least empty table)
        MultiOptionDialogButton.prefix          - button's prefix text (nillable)
    
    MultiOptionDialogButtonOption API:
        MultiOptionDialogButtonOption.create(data?)     -> data is an existing MultiOptionDialogButtonOption object to make another copy of.
        MultiOptionDialogButtonOption.previewCallback   - callback function called upon the option being cycled to by a button click.
        MultiOptionDialogButtonOption.name              - option name to be displayed on button.
]]

---@class MultiOptionDialog
---@field callback fun(dialog: MultiOptionDialog, player: player, buttonChosenOptionPairs: table<MultiOptionDialogButton, MultiOptionDialogButtonOption>)
---@field buttons MultiOptionDialogButton[]
---@field commitButton DialogButtonWrapper
---@field title string
MultiOptionDialog = {}
MultiOptionDialog.__index = MultiOptionDialog

---@param data? MultiOptionDialog
---@return MultiOptionDialog
function MultiOptionDialog.create(data)
    local instance = setmetatable({}, MultiOptionDialog)
    instance.buttons = {}
    if data ~= nil then
        for _, button in ipairs(data.buttons) do
            table.insert(instance.buttons, MultiOptionDialogButton.create(button))
        end

        instance.callback = data.callback
        instance.title = data.title
        instance.commitButton = DialogButtonWrapper.create(data.commitButton)
    end
    return instance
end

---@class MultiOptionDialogButton
---@field options MultiOptionDialogButtonOption[]
---@field prefix string
---@field messageFormat string
---@field hotkey string
MultiOptionDialogButton = {}
MultiOptionDialogButton.__index = MultiOptionDialogButton

---@param data? MultiOptionDialogButton
---@return MultiOptionDialogButton
function MultiOptionDialogButton.create(data)
    local instance = setmetatable({}, MultiOptionDialogButton)
    instance.options = {}
    
    if data ~= nil then
        for _, option in ipairs(data.options) do
            table.insert(instance.options, MultiOptionDialogButtonOption.create(option))
        end
        instance.messageFormat = data.messageFormat
        instance.prefix = data.prefix
        instance.hotkey = data.hotkey
    else
        instance.messageFormat = "[\x25s] \x25s"
    end
    return instance
end

---@class MultiOptionDialogButtonOption
---@field previewCallback fun(player: player)
---@field name string
MultiOptionDialogButtonOption = {}
MultiOptionDialogButtonOption.__index = MultiOptionDialogButtonOption

---@param data? MultiOptionDialogButtonOption
---@return MultiOptionDialogButtonOption
function MultiOptionDialogButtonOption.create(data)
    local instance = setmetatable({}, MultiOptionDialogButtonOption)
    if data ~= nil then
        instance.previewCallback = data.previewCallback
        instance.name = data.name
    end
    return instance
end

-- Internal Classes
---@class MultiDialogWrapper : DialogWrapper
---@field buttons MultiDialogButtonWrapper[]
---@field _dialogDef MultiOptionDialog

---@class MultiDialogButtonWrapper : DialogButtonWrapper
---@field _buttonDef MultiOptionDialogButton
---@field _option integer

---@class DialogPlayerData
---@field players Set
---@field playerDialogWrappers table<player, MultiDialogWrapper>

---@param button MultiDialogButtonWrapper
---@param dialog MultiDialogWrapper
---@param player player
local function cycleOption(button, dialog, player)
    button._option = button._option + 1
    local buttonDef = button._buttonDef
    if button._option > #buttonDef.options then
        button._option = 1
    end
    local option = buttonDef.options[button._option]
    option.previewCallback(player)
    button.text = string.format(buttonDef.messageFormat, buttonDef.prefix, option.name)
    DialogQueue.EnqueueAfterCurrentDialog(dialog, player)
end

local queuedDialogsForPlayers = {} ---@type table<MultiOptionDialog, DialogPlayerData>

---@param dialog MultiOptionDialog
---@param player player
local function dequeuePlayer(dialog, player)
    local playerDialogData = queuedDialogsForPlayers[dialog]
    playerDialogData.players:removeSingle(player)
    if playerDialogData.players:isEmpty() then
        queuedDialogsForPlayers[dialog] = nil
    end
end

---@param dialog MultiDialogWrapper
---@param player player
local function commitOptions(_, dialog, player)
    local selectedButtonOptions = {} ---@type table<MultiOptionDialogButton, MultiOptionDialogButtonOption>

    for _, thisButton in ipairs(dialog.buttons) do
        if thisButton._buttonDef then -- last button is not MultiOptionDialogButton, just a normal DialogButtonWrapper
            selectedButtonOptions[thisButton._buttonDef] = thisButton._buttonDef.options[thisButton._option]
        end
    end

    dialog._dialogDef.callback(dialog._dialogDef, player, selectedButtonOptions)
    dequeuePlayer(dialog._dialogDef, player)
end

---@param dialogDef MultiOptionDialog
---@return DialogWrapper
local function toDialogWrapper(dialogDef)

    local dialogWrapper = { 
        triggers = {},
        buttons = {},
        messageText = dialogDef.title,
        callback = nil,
        quitButton = nil,
    } --[[@as DialogWrapper]]

    for _, buttonDef in ipairs(dialogDef.buttons) do
        table.insert(dialogWrapper.buttons, {
            text = string.format(buttonDef.messageFormat, buttonDef.prefix, buttonDef.options[1].name),
            hotkey = string.byte(buttonDef.hotkey) or 0,
            triggers = {},
            callback = cycleOption,
            _buttonDef = buttonDef
        })
    end

    if dialogDef.commitButton then
        table.insert(dialogWrapper.buttons, {
            text = dialogDef.commitButton.text,
            hotkey = dialogDef.commitButton.hotkey,
            triggers = dialogDef.commitButton.triggers,
            callback = commitOptions
        }) 
    else
        table.insert(dialogWrapper.buttons, {
            text = "Done",
            hotkey = 0,
            triggers = {},
            callback = commitOptions
        })
    end

    return dialogWrapper
end

---@param players Set
---@return boolean success
function MultiOptionDialog:Enqueue(players)
    if queuedDialogsForPlayers[self] ~= nil then
        return false
    end
    local dialogWrapper = toDialogWrapper(self)
    local playerDialogData = {
        players = players,
        playerDialogWrappers = {}
    }
    queuedDialogsForPlayers[self] = playerDialogData

    for player in players:elements() do 
        local playerDialog = DialogWrapper.create(dialogWrapper) --[[@as MultiDialogWrapper]]
        playerDialog._dialogDef = self

        for index, button in ipairs(playerDialog.buttons) do
            button._option = 1
            button._buttonDef = self.buttons[index]
        end
        playerDialogData.playerDialogWrappers[player] = playerDialog
        DialogQueue.Enqueue(playerDialog, player)
    end

    return true

end

---@param players Set
---@return boolean success
function MultiOptionDialog:Dequeue(players)

    if queuedDialogsForPlayers[self] ~= nil then
        return false
    end

    local playersToDequeue = Set.intersection(players, queuedDialogsForPlayers[self].players)

    queuedDialogsForPlayers[self].players:removeAll(playersToDequeue)
    for player --[[@as player]] in playersToDequeue:elements() do
        dequeuePlayer(self, player)
        DialogQueue.Dequeue(queuedDialogsForPlayers[self].playerDialogWrappers[player], player)
    end

    return true

end
end