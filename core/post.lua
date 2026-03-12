module 'aux.core.post'

local aux = require 'aux'
local info = require 'aux.util.info'
local stack = require 'aux.core.stack'
local history = require 'aux.core.history'
local disenchant = require 'aux.core.disenchant'

local state

[[ Algorithmic Posting Parameters ]]
local function evaluatePostPrice(itemString, currentLowestBuyout)
    [[ Assuming GetTSMMarketValue was added to the history module ]]
    local marketValue = history.GetTSMMarketValue(itemString)
    
    [[ Establish floor and ceiling prices ]]
    local minPrice = math.floor(marketValue * 0.80)
    local normalPrice = math.floor(marketValue * 1.20)
    local maxPrice = math.floor(marketValue * 2.00)
    
    [[ Execute conditional routing ]]
    if currentLowestBuyout < minPrice then
        [[ Market crashed: default to normal valuation ]]
        return normalPrice
    elseif currentLowestBuyout > maxPrice then
        [[ Market inflated: cap at maximum valuation ]]
        return maxPrice
    else
        [[ Standard market: fractional undercut ]]
        return math.floor(currentLowestBuyout * 0.999)
    end
end

function aux.handle.CLOSE()
    stop()
end

function process()
    if state.posted < state.count then

        local stacking_complete

        local send_signal, signal_received = aux.signal()
        aux.when(signal_received, function()
            local slot = signal_received()[1]
            if slot then
                return post_auction(slot, process)
            else
                return stop()
            end
        end)

        return stack.start(state.item_key, state.stack_size, send_signal)
    end

    return stop()
end

function post_auction(slot, k)
    local item_info = info.container_item(unpack(slot))
    if item_info.item_key == state.item_key and info.auctionable(item_info.tooltip, nil, true) and item_info.aux_quantity == state.stack_size then

        ClearCursor()
        ClickAuctionSellItemButton()
        ClearCursor()
        PickupContainerItem(unpack(slot))
        ClickAuctionSellItemButton()
        ClearCursor()
        
        local start_price = state.unit_start_price
        local buyout_price = state.unit_buyout_price
        
        [[ Assign evaluated price to the listing ]]
        local newListingPrice = evaluatePostPrice(state.item_key, buyout_price)
        buyout_price = newListingPrice
        start_price = math.floor(buyout_price * 0.95)
        
        StartAuction(max(1, aux.round(start_price * item_info.aux_quantity)), aux.round(buyout_price * item_info.aux_quantity), state.duration)

        local send_signal, signal_received = aux.signal()
        aux.when(signal_received, function()
            state.posted = state.posted + 1
            return k()
        end)

        local posted
        aux.event_listener('CHAT_MSG_SYSTEM', function(kill)
            if arg1 == ERR_AUCTION_STARTED then
                send_signal()
                kill()
            end
        end)
    else
        return stop()
    end
end

function M.stop()
    if state then
        aux.kill_thread(state.thread_id)

        local callback = state.callback
        local posted = state.posted

        state = nil

        if callback then
            callback(posted)
        end
    end
end

function M.start(item_key, stack_size, duration, unit_start_price, unit_buyout_price, count, callback)
    stop()
    state = {
        thread_id = aux.thread(process),
        item_key = item_key,
        stack_size = stack_size,
        duration = duration,
        unit_start_price = unit_start_price,
        unit_buyout_price = unit_buyout_price,
        count = count,
        posted = 0,
        callback = callback,
    }
end
