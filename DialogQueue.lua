if Debug then Debug.beginFile "DialogQueue" end
OnInit.root("DialogQueue", function(require)
    --[[
    DialogQueue v1.2 by Insanity_AI
    ------------------------------------------------------------------------------
    A system that fixes WC3's default dialog behavior by hijacking Dialog natives:
        - Calling DialogDisplay on a new dialog when another dialog is currently being displayed
          will no longer hide the currently displayed dialog to show the new dialog, but will wait
          for the old dialog to be clicked (or hidden) before showing the new dialog.
        - Calling DialogClear on dialogs being currently shown will not just wipe all its content
          and keep displaying a blank dialog to player, but will hide the dialog as well.

    Additionally:
        - Calling DialogDisplay or DialogDestroy on a dialog that is queued up will remove it from the queue, as it is blank.
        - Will always execute dialog events first, and then dialog button events.
        - Can be used without native override, and with callback functions instead of triggers.

    Requires:
        Total Initialization - https://www.hiveworkshop.com/threads/total-initialization.317099/
        SetUtils - https://www.hiveworkshop.com/threads/setutils.353716/
        Defintive Doubly Linked List - https://www.hiveworkshop.com/threads/definitive-doubly-linked-list.354885/

    Installation:
        To enable dialog native override (for GUI), either call DialogQueue.NativeOverride on Map Initialization
            Or have TotalInitialization and set OVERRIDE_NATIVES to true.]]
    local OVERRIDE_NATIVES = true
    local OVERRIDE_GET_TRIGGERING_PLAYER = false --works only if OVERRIDE_NATIVES is also true.
    --[[    Additionally, call DialogQueue.Init function on Game Start, if TotalInitialization is not present.

Hijacked Natives API:
    DialogCreate -> returns a DialogWrapper object
    DialogDestroy -> clears DialogWrapper's content and dequeues it from player queues.
    DialogClear -> same as DialogDestroy
    DialogSetMessage -> sets DialogWrapper's messageText property
    DialogAddButton -> adds a new DialogButtonWrapper object to DialogWrapper with text and hotkey.
    DialogAddQuitButton -> same as DialogAddButton but with quit functionality.
    DialogDisplay -> Enqueues or Dequeues the dialog to/from player's dialog queue (depending on flag argument)
    TriggerRegisterDialogEvent -> Adds the trigger to DialogWrapper object to be executed when dialog is clicked on.
    TriggerRegisterDialogButtonEvent -> Adds the trigger to DialogButtonWrapper object to be executed when dialog is clicked on.

    GetClickedButton -> returns DialogButtonWrapper object that was clicked.
    GetClickedDialog -> returns DialogWrapper object that was clicked.
    GetTriggerPlayer -> returns the player that did the clicking, if it was dialog related. Otherwise does what GetTriggerPlayer usually does.

DialogWrapper API:
    DialogWrapper.create(data?) -> creates a new dialog object to be used for this system.
                                -> data can be an existing DialogWrapper object to make another copy of.
    DialogWrapper.triggers      - array of triggers to be executed when dialog is clicked. (not nillable, must be at least empty table.)
    DialogWrapper.callback      - callback function for when dialog has been clicked.
    DialogWrapper.messageText   - Title text for dialog. (nillable)
    DialogWrapper.buttons       - array of DialogButtonWrapper objects (not nillable, must be at least empty table.)
    DialogWrapper.quitButton    - single DialogQuitButtonWrapper object (nillable)

DialogButtonWrapper API:
    DialogButtonWrapper.create(data)    -> creates a new DialogButtonWrapper
                                        -> data is an existing DialogButtonWrapper object to make another copy of.
    DialogButtonWrapper.text        - button's text (nillable)
    DialogButtonWrapper.hotkey      - button's hotkey (must be either integer or nillable)
    DialogButtonWrapper.triggers    - array of triggers to be executed when the button is clicked. (not nillable, must be at least empty table)
    DialogButtonWrapper.callback    - callback function for when dialog button has been clicked.

DialogQuitButtonWrapper API: (extension of DialogButtonWrapper)
    DialogQuitButtonWrapper.create(data)    -> creates a new DialogQuitButtonWrapper
                                            -> data is an existing DialogQuitButtonWrapper object to make another copy of.
    DialogQuitButtonWrapper.doScoreScreen - must be true or false (not nillable)

DialogQueue API:
    DialogQueue.Enqueue(dialogWrapper, player) -> queues up a dialog for the player
    DialogQueue.EnqueueAfterCurrentDialog(dialogWrapper, player) -> queues up a dialog right after the current dialog that is being displayed right now.
    DialogQueue.Dequeue(dialogWrapper, player) -> dequeues a dialog for the player
    DialogQueue.SkipCurrentDialog -> skips currently displayed dialog.

Functionality:
    - Creates a single dialog for each player in the game, all registered to the same trigger that processes dialog clicks
        and passes them to respective triggers/callback functions. These WC3 dialogs are never removed but rather cleared and
        set with different buttons and messages.
    - Creates a single queue for each player designated to store DialogWrappers and show them sequentially in the queue order.
    - When a player presses a dialog button, the currently displayed dialog is removed from that player's queue and the system
        will show the next queued dialog, if there is any.
    - Queueing up a dialog when there are no dialogs in the queue will immediately display it to the player.
    - If the dialog has no buttons defined, the dialog will be skipped just before being displayed.
]]

    ---@class DialogWrapper
    ---@field triggers trigger[]
    ---@field callback fun(dialog: DialogWrapper, player: player)?
    ---@field messageText string
    ---@field buttons DialogButtonWrapper[]
    ---@field quitButton DialogQuitButtonWrapper?
    DialogWrapper = {}
    DialogWrapper.__index = DialogWrapper

    ---@param data? DialogWrapper
    ---@return DialogWrapper
    function DialogWrapper.create(data)
        local instance = setmetatable({}, DialogWrapper)

        instance.buttons = {}
        instance.triggers = {}
        if data ~= nil then
            for _, button in ipairs(data.buttons) do
                table.insert(instance.buttons, DialogButtonWrapper.create(button))
            end

            instance.triggers = {}
            for _, trigger in ipairs(data.triggers) do
                table.insert(instance.triggers, trigger)
            end

            instance.callback = data.callback
            instance.messageText = data.messageText

            if data.quitButton then
                instance.quitButton = DialogQuitButtonWrapper.create(data.quitButton)
            end
        end

        return instance
    end

    ---@class DialogButtonWrapper
    ---@field text string
    ---@field hotkey integer|nil --1 character only
    ---@field triggers trigger[]?
    ---@field callback fun(button: DialogButtonWrapper, dialog: DialogWrapper, player: player)?
    DialogButtonWrapper = {}
    DialogButtonWrapper.__index = DialogButtonWrapper

    ---@param data? DialogButtonWrapper
    ---@return DialogButtonWrapper
    function DialogButtonWrapper.create(data)
        local instance = setmetatable({}, DialogButtonWrapper)
        instance.triggers = {}
        if data ~= nil then
            instance.text = data.text
            instance.hotkey = data.hotkey
            instance.callback = data.callback
        end
        return instance
    end

    ---@class DialogQuitButtonWrapper : DialogButtonWrapper
    ---@field doScoreScreen boolean
    DialogQuitButtonWrapper = {}
    DialogQuitButtonWrapper.__index = DialogQuitButtonWrapper
    setmetatable(DialogQuitButtonWrapper, DialogButtonWrapper)

    ---@param data? DialogQuitButtonWrapper
    ---@return DialogQuitButtonWrapper
    function DialogQuitButtonWrapper.create(data)
        local instance = setmetatable(DialogButtonWrapper(data), DialogQuitButtonWrapper)
        if data ~= nil then
            instance.doScoreScreen = data.doScoreScreen
        end
        return instance --[[@as DialogQuitButtonWrapper]]
    end

    local oldDialogCreate = DialogCreate
    -- local oldDialogDestroy = DialogDestroy
    local oldDialogClear = DialogClear
    local oldDialogSetMessage = DialogSetMessage
    local oldDialogAddButton = DialogAddButton
    local oldDialogAddQuitButton = DialogAddQuitButton
    local oldDialogDisplay = DialogDisplay

    local oldTriggerRegisterDialogEvent = TriggerRegisterDialogEvent
    -- local oldTriggerRegisterDialogButtonEvent = TriggerRegisterDialogButtonEvent

    local oldGetClickedButton = GetClickedButton
    -- local oldGetClickedDialog = GetClickedDialog

    local oldGetTriggerPlayer = GetTriggerPlayer

    DialogQueue = {}

    local playerQueueActive = {} ---@type table<player, boolean>
    local dialogQueues = {} ---@type table<player, LinkedListHead>
    local playerDialog = {} ---@type table<player, dialog>
    local currentDialogButtons = {} ---@type table<player, table<button, DialogButtonWrapper>>

    ---@param player player
    local function displayNextDialog(player)
        if playerQueueActive[player] ~= nil then
            return -- is active
        end

        local playerQueue = dialogQueues[player]
        if playerQueue.n <= 0 then
            return -- empty nothing to show.
        end

        playerQueueActive[player] = true

        local dialog = playerDialog[player]
        local dialogDefinition = playerQueue.next.value --[[@as DialogWrapper]]

        oldDialogDisplay(player, dialog, false)
        oldDialogClear(dialog)
        if type(dialogDefinition.messageText) == "string" then
            oldDialogSetMessage(dialog, dialogDefinition.messageText)
        end

        currentDialogButtons[player] = {}
        if #dialogDefinition.buttons == 0 and dialogDefinition.quitButton == nil then
            -- dialog has no buttons, skip and show next dialog.
            DialogQueue.SkipCurrentDialog(player)
            playerQueueActive[player] = false
            displayNextDialog(player)
            return
        end

        for _, buttonDefinition in ipairs(dialogDefinition.buttons) do
            local button = oldDialogAddButton(dialog, buttonDefinition.text, buttonDefinition.hotkey)
            currentDialogButtons[player][button] = buttonDefinition
        end

        if dialogDefinition.quitButton ~= nil then
            local quitButton = oldDialogAddQuitButton(dialog, dialogDefinition.quitButton.doScoreScreen,
                dialogDefinition.quitButton.text, dialogDefinition.quitButton.hotkey)
            currentDialogButtons[player][quitButton] = dialogDefinition.quitButton
        end

        oldDialogDisplay(player, dialog, true)
    end

    ---@param dialog DialogWrapper
    ---@param player player
    function DialogQueue.Enqueue(dialog, player)
        dialogQueues[player]:insert(dialog)
        displayNextDialog(player)
    end

    ---@param dialog DialogWrapper
    ---@param player player
    function DialogQueue.EnqueueAfterCurrentDialog(dialog, player)
        dialogQueues[player]:insert(dialog, true)
    end

    ---@param dialog DialogWrapper
    ---@param player player
    function DialogQueue.Dequeue(dialog, player)
        if dialogQueues[player].n <= 0 then
            return
        end

        -- is currently displayed dialog being dequeued?
        if dialogQueues[player].next.value --[[@as DialogWrapper]] == dialog then
            DialogQueue.SkipCurrentDialog(player)
            return
        end

        for thisDialog in dialogQueues[player]:loop() do
            if thisDialog.value --[[@as DialogWrapper]] == dialog then
                thisDialog --[[@as LinkedListNode]]:remove()
                break
            end
        end
    end

    ---@param player player
    function DialogQueue.SkipCurrentDialog(player)
        playerQueueActive[player] = nil
        dialogQueues[player].next:remove()
        displayNextDialog(player)
    end

    local weakTableSetup = { __mode = "kv" }
    local threadPlayer = setmetatable({}, weakTableSetup) ---@type table<thread, player>
    local threadDialog = setmetatable({}, weakTableSetup) ---@type table<thread, DialogWrapper>
    local threadButton = setmetatable({}, weakTableSetup) ---@type table<thread, DialogButtonWrapper>

    if OVERRIDE_NATIVES then
        OnInit.root(function(require)
            -- Event callbacks
            -- Decided to add special config option since this one is a bit more generic, and widely used instead of for just dialogs.
            if OVERRIDE_GET_TRIGGERING_PLAYER then
                ---@return player
                GetTriggerPlayer = function()
                    local triggerPlayer = oldGetTriggerPlayer()
                    if oldGetTriggerPlayer() == nil then
                        triggerPlayer = threadPlayer[coroutine.running()]
                    end

                    return triggerPlayer
                end
            end

            ---@return DialogWrapper
            GetClickedDialog = function()
                return threadDialog[coroutine.running()]
            end

            ---@return DialogButtonWrapper
            GetClickedButton = function()
                return threadButton[coroutine.running()]
            end

            -- Event registry
            ---@param trigger trigger
            ---@param dialog DialogWrapper
            TriggerRegisterDialogEvent = function(trigger, dialog)
                table.insert(dialog.triggers, trigger)
            end

            ---@param trigger trigger
            ---@param button DialogButtonWrapper
            TriggerRegisterDialogButtonEvent = function(trigger, button)
                table.insert(button.triggers, trigger)
            end

            -- Dialog API
            DialogCreate = DialogWrapper.create

            ---@param dialog DialogWrapper
            DialogDestroy = function(dialog)
                for player in SetUtils.getPlayersAll():elements() do
                    DialogQueue.Dequeue(dialog, player)
                end
                dialog.buttons = {}
                dialog.messageText = nil
                dialog.quitButton = nil
                dialog.triggers = {}
            end
            DialogClear = DialogDestroy

            ---@param dialog DialogWrapper
            ---@param messageText string
            DialogSetMessage = function(dialog, messageText)
                dialog.messageText = messageText
            end

            ---@param dialog DialogWrapper
            ---@param buttonText string
            ---@param hotkey integer
            ---@return DialogButtonWrapper
            DialogAddButton = function(dialog, buttonText, hotkey)
                local button = DialogButtonWrapper.create()
                button.text = buttonText
                button.hotkey = hotkey
                table.insert(dialog.buttons, button)
                return button
            end

            ---@param dialog DialogWrapper
            ---@param doScoreScreen boolean
            ---@param buttonText string
            ---@param hotkey integer
            ---@return DialogButtonWrapper
            DialogAddQuitButton = function(dialog, doScoreScreen, buttonText, hotkey)
                local button = DialogQuitButtonWrapper.create()
                button.text = buttonText
                button.hotkey = hotkey
                button.doScoreScreen = doScoreScreen
                dialog.quitButton = button
                return button
            end

            ---@param player player
            ---@param dialog DialogWrapper
            ---@param show boolean
            DialogDisplay = function(player, dialog, show)
                if show then
                    DialogQueue.Enqueue(dialog, player)
                else
                    DialogQueue.Dequeue(dialog, player)
                end
            end
        end)
    end

    ---@param triggers trigger[]
    local callTriggers = function(triggers)
        for _, trigger in ipairs(triggers) do
            if trigger ~= nil then
                if TriggerEvaluate(trigger) then
                    TriggerExecute(trigger)
                end
            end
        end
    end

    local function callTriggersInCoroutine(triggerPlayer, dialog, button)
        local thread = coroutine.running()
        threadPlayer[thread] = triggerPlayer
        threadDialog[thread] = dialog
        threadButton[thread] = button

        callTriggers(dialog.triggers)
        callTriggers(button.triggers)
    end

    OnInit.final(function(require)
        require "SetUtils"
        require "LinkedList"

        local trigger = CreateTrigger()

        for player in SetUtils.getPlayersAll():elements() do
            local dialog = oldDialogCreate() -- dialog per player
            playerDialog[player] = dialog --[[@as dialog]]
            dialogQueues[player] = LinkedList.create()
            oldTriggerRegisterDialogEvent(trigger, dialog)
        end

        TriggerAddAction(trigger, function()
            local triggerPlayer = oldGetTriggerPlayer()
            local dialogNode = dialogQueues[triggerPlayer].next --[[@as LinkedListNode]]
            local dialog = dialogNode.value --[[@as DialogWrapper]]
            local actualButton = oldGetClickedButton() --[[@as button]]
            local button = currentDialogButtons[triggerPlayer][actualButton]
            callTriggersInCoroutine(triggerPlayer, dialog, button)

            if dialog.callback ~= nil then dialog:callback(triggerPlayer) end
            if button.callback ~= nil then button:callback(dialog, triggerPlayer) end

            local status, err = pcall(dialogNode.remove, dialogNode)
            if status ~= true then
                warn("Failed removing Dialog Node from Linked List. This is caused by the DialogWrapper being Dequeued by the callback function. In the future, please avoid this!")
                warn("Error: " .. err)
            end
            playerQueueActive[triggerPlayer] = nil
            displayNextDialog(triggerPlayer)
        end)
    end)
end)
if Debug then Debug.endFile() end
