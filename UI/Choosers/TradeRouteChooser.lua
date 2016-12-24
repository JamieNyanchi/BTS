-- ===========================================================================
--  Settings
-- ===========================================================================

local alignTradeRouteYields = true
local showSortOrdersPermanently = false

-- ===========================================================================
--  INCLUDES
-- ===========================================================================

include("InstanceManager");
include("SupportFunctions");
include("TradeSupport");

-- ===========================================================================
--  CONSTANTS
-- ===========================================================================

local SORT_BY_ID:table = GetSortByIdConstants();
local SORT_ASCENDING = GetSortAscendingIdConstant();
local SORT_DESCENDING = GetSortDescendingIdConstant();

-- ===========================================================================
--  VARIABLES
-- ===========================================================================

local m_RouteChoiceIM           : table = InstanceManager:new("RouteChoiceInstance", "Top", Controls.RouteChoiceStack);
local m_originCity              : table = nil;  -- City where the trade route will begin
local m_destinationCity         : table = nil;  -- City where the trade route will end, nil if none selected
local m_pTradeOverviewContext   : table = nil;  -- Trade Overview context

-- These can be set by other contexts to have a route selected automatically after the chooser opens
local m_postOpenSelectPlayerID:number = -1;
local m_postOpenSelectCityID:number = -1;

-- Filtered and unfiltered lists of possible destinations
local m_unfilteredDestinations:table = {};
local m_filteredDestinations:table = {};

-- Stores filter list and tracks the currently selected list
local m_filterList:table = {};
local m_filterCount:number = 0;
local m_filterSelected:number = 1;

local m_shiftDown:boolean = false;

-- Stores the sort settings.
local m_SortBySettings = {};

-- Default is ascending in turns to complete trade route
m_SortBySettings[1] = {
    SortByID = SORT_BY_ID.TURNS_TO_COMPLETE,
    SortOrder = SORT_ASCENDING
};

-- ===========================================================================
--  Refresh functions
-- ===========================================================================
function Refresh()
    local selectedUnit:table = UI.GetHeadSelectedUnit();
    if selectedUnit == nil then
        Close();
        return;
    end

    m_originCity = Cities.GetCityInPlot(selectedUnit:GetX(), selectedUnit:GetY());
    if m_originCity == nil then
        Close();
        return;
    end

    RefreshHeader();

    RefreshTopPanel();

    RefreshSortBar();

    RefreshChooserPanel();
end

function RefreshHeader()
    if m_originCity then
        Controls.Header_OriginText:SetText(Locale.Lookup("LOC_ROUTECHOOSER_TO_DESTINATION", Locale.ToUpper(m_originCity:GetName())));
    end
end

function RefreshTopPanel()
    if m_destinationCity and m_originCity then
        -- Update City Banner
        Controls.CityName:SetText(Locale.ToUpper(m_destinationCity:GetName()));

        local backColor:number, frontColor:number  = UI.GetPlayerColors( m_destinationCity:GetOwner() );
        local darkerBackColor:number = DarkenLightenColor(backColor,(-85),238);
        local brighterBackColor:number = DarkenLightenColor(backColor,90,255);

        Controls.BannerBase:SetColor( backColor );
        Controls.BannerDarker:SetColor( darkerBackColor );
        Controls.BannerLighter:SetColor( brighterBackColor );
        Controls.CityName:SetColor( frontColor );

        -- Update Trading Post Icon
        if m_destinationCity:GetTrade():HasActiveTradingPost(m_originCity:GetOwner()) then
            Controls.TradingPostIcon:SetHide(false);
        else
            Controls.TradingPostIcon:SetHide(true);
        end

        -- Update City-State Quest Icon
        Controls.CityStateQuestIcon:SetHide(true);
        local questsManager : table = Game.GetQuestsManager();
        local questTooltip  : string = Locale.Lookup("LOC_CITY_STATES_QUESTS");
        if (questsManager ~= nil and Game.GetLocalPlayer() ~= nil) then
            local tradeRouteQuestInfo:table = GameInfo.Quests["QUEST_SEND_TRADE_ROUTE"];
            if (tradeRouteQuestInfo ~= nil) then
                if (questsManager:HasActiveQuestFromPlayer(Game.GetLocalPlayer(), m_destinationCity:GetOwner(), tradeRouteQuestInfo.Index)) then
                    questTooltip = questTooltip .. "[NEWLINE]" .. tradeRouteQuestInfo.IconString .. questsManager:GetActiveQuestName(Game.GetLocalPlayer(), m_destinationCity:GetOwner(), tradeRouteQuestInfo.Index);
                    Controls.CityStateQuestIcon:SetHide(false);
                    print("Setting tooltip to " .. questTooltip);
                    Controls.CityStateQuestIcon:SetToolTipString(questTooltip);
                end
            end
        end

        -- Update turns to complete route
        local tradeRoute = {
            OriginCityPlayer        = m_originCity:GetOwner(),
            OriginCityID            = m_originCity:GetID(),
            DestinationCityPlayer   = m_destinationCity:GetOwner(),
            DestinationCityID       = m_destinationCity:GetID()
        };

        local tradePathLength, tripsToDestination, turnsToCompleteRoute = GetRouteInfo(tradeRoute);
        Controls.TurnsToComplete:SetColor( frontColor );
        Controls.TurnsToComplete:SetText(turnsToCompleteRoute);

        -- Update Resource Lists
        local originReceivedResources:boolean = false;
        local originTooltipText:string = "";
        Controls.OriginResourceList:DestroyAllChildren();
        for yieldInfo in GameInfo.Yields() do
            local yieldValue, sourceText = GetYieldForCity(yieldInfo.Index, m_destinationCity, true);
            if (yieldValue > 0 ) or alignTradeRouteYields then
                if (originTooltipText ~= "" and (yieldValue > 0)) then
                    originTooltipText = originTooltipText .. "[NEWLINE]";
                end
                originTooltipText = originTooltipText .. sourceText;

                -- Custom offset because of background texture
                if (yieldInfo.YieldType == "YIELD_FOOD") then
                    AddResourceEntry(yieldInfo, yieldValue, sourceText, Controls.OriginResourceList, 5);
                else
                    AddResourceEntry(yieldInfo, yieldValue, sourceText, Controls.OriginResourceList);
                end

                originReceivedResources = true;
            end
        end
        Controls.OriginResources:SetToolTipString(originTooltipText);
        Controls.OriginResourceHeader:SetText(Locale.Lookup("LOC_ROUTECHOOSER_RECEIVES_RESOURCE", Locale.Lookup(m_originCity:GetName())));
        Controls.OriginResourceList:ReprocessAnchoring();

        if originReceivedResources then
            Controls.OriginReceivesNoBenefitsLabel:SetHide(true);
        else
            Controls.OriginReceivesNoBenefitsLabel:SetHide(false);
        end

        local destinationReceivedResources:boolean = false;
        local destinationTooltipText:string = "";
        Controls.DestinationResourceList:DestroyAllChildren();
        for yieldInfo in GameInfo.Yields() do
            local yieldValue, sourceText = GetYieldForCity(yieldInfo.Index, m_destinationCity, false);
            if (yieldValue > 0 ) or alignTradeRouteYields then
                if (destinationTooltipText ~= "") then
                    destinationTooltipText = destinationTooltipText .. "[NEWLINE]";
                end
                destinationTooltipText = destinationTooltipText .. sourceText;
                AddResourceEntry(yieldInfo, yieldValue, sourceText, Controls.DestinationResourceList);

                if yieldValue > 0 then
                    destinationReceivedResources = true;
                end
            end
        end
        Controls.DestinationResources:SetToolTipString(destinationTooltipText);
        Controls.DestinationResourceHeader:SetText(Locale.Lookup("LOC_ROUTECHOOSER_RECEIVES_RESOURCE", Locale.Lookup(m_destinationCity:GetName())));
        Controls.DestinationResourceList:ReprocessAnchoring();

        if destinationReceivedResources then
            Controls.DestinationReceivesNoBenefitsLabel:SetHide(true);
        else
            Controls.DestinationReceivesNoBenefitsLabel:SetHide(false);
        end

        -- Show Panel
        Controls.CurrentSelectionContainer:SetHide(false);

        -- Hide Status Message
        Controls.StatusMessage:SetHide(true);
    else
        -- Hide Panel
        Controls.CurrentSelectionContainer:SetHide(true);

        -- Show Status Message
        Controls.StatusMessage:SetHide(false);
    end
end

function RefreshChooserPanel()
    local tradeManager:table = Game.GetTradeManager();

    -- Reset Destinations
    m_unfilteredDestinations = {};

    local players:table = Game:GetPlayers();
    for i, player in ipairs(players) do
        local cities:table = player:GetCities();
        for j, city in cities:Members() do
            -- Can we start a trade route with this city?
            if tradeManager:CanStartRoute(m_originCity:GetOwner(), m_originCity:GetID(), city:GetOwner(), city:GetID()) then
                table.insert(m_unfilteredDestinations, city);
            end
        end
    end

    -- Update Filters
    RefreshFilters();

    -- Update Destination Choice Stack
    RefreshStack();

    -- Send Trade Route Paths to Engine
    UILens.ClearLayerHexes( LensLayers.TRADE_ROUTE );

    local pathPlots     : table = {};
    for index, city in ipairs(m_filteredDestinations) do
        pathPlots = tradeManager:GetTradeRoutePath(m_originCity:GetOwner(), m_originCity:GetID(), city:GetOwner(), city:GetID() );
        local kVariations:table = {};
        local lastElement : number = table.count(pathPlots);
        table.insert(kVariations, {"TradeRoute_Destination", pathPlots[lastElement]} );
        UILens.SetLayerHexesPath( LensLayers.TRADE_ROUTE, Game.GetLocalPlayer(), pathPlots, kVariations );
    end
end

-- ===========================================================================
--  Routes stack Function
-- ===========================================================================

function RefreshStack()
    local tradeManager:table = Game.GetTradeManager();
    local tradeRoutes = {}

    -- Filter Destinations by active Filter
    if m_filterList[m_filterSelected].FilterFunction ~= nil then
        m_filterList[m_filterSelected].FilterFunction();
    else
        m_filteredDestinations = m_unfilteredDestinations;
    end

    -- Create trade routes to be sorted
    for index, city in ipairs(m_filteredDestinations) do
        local tradeRoute = {
            OriginCityPlayer        = m_originCity:GetOwner(),
            OriginCityID            = m_originCity:GetID(),
            DestinationCityPlayer   = city:GetOwner(),
            DestinationCityID       = city:GetID()
        };

        table.insert(tradeRoutes, tradeRoute)
    end

    SortTradeRoutes( tradeRoutes, m_SortBySettings );

    -- Add Destinations to Stack
    m_RouteChoiceIM:ResetInstances();

    local numberOfDestinations:number = 0;
    for index, tradeRoute in ipairs(tradeRoutes) do
        -- print("Adding route: " .. getTradeRouteString( tradeRoute ))

        local destinationPlayer:table = Players[tradeRoute.DestinationCityPlayer];
        local destinationCity:table = destinationPlayer:GetCities():FindID(tradeRoute.DestinationCityID);

        AddCityToDestinationStack(destinationCity);
        numberOfDestinations = numberOfDestinations + 1;
    end

    Controls.RouteChoiceStack:CalculateSize();
    Controls.RouteChoiceScrollPanel:CalculateSize();

    -- Adjust offset to center destination scrollpanel/stack
    if Controls.RouteChoiceScrollPanel:GetScrollBar():IsHidden() then
        Controls.RouteChoiceScrollPanel:SetOffsetX(5);
    else
        Controls.RouteChoiceScrollPanel:SetOffsetX(13);
    end

    -- Show No Available Trade Routes message if nothing to select
    if numberOfDestinations > 0 then
        Controls.StatusMessage:SetText(Locale.Lookup("LOC_ROUTECHOOSER_SELECT_DESTINATION"));
    else
        Controls.StatusMessage:SetText(Locale.Lookup("LOC_ROUTECHOOSER_NO_TRADE_ROUTES"));
    end
end

function AddCityToDestinationStack(city:table)
    local cityEntry:table = m_RouteChoiceIM:GetInstance();

    -- Update Selector Brace
    if m_destinationCity ~= nil and city:GetName() == m_destinationCity:GetName() then
        cityEntry.SelectorBrace:SetHide(false);
    else
        cityEntry.SelectorBrace:SetHide(true);
    end

    -- Setup city banner
    cityEntry.CityName:SetText(Locale.ToUpper(city:GetName()));

    local backColor:number, frontColor:number  = UI.GetPlayerColors( city:GetOwner() );
    local darkerBackColor:number = DarkenLightenColor(backColor,(-85),238);
    local brighterBackColor:number = DarkenLightenColor(backColor,90,255);

    cityEntry.BannerBase:SetColor( backColor );
    cityEntry.BannerDarker:SetColor( darkerBackColor );
    cityEntry.BannerLighter:SetColor( brighterBackColor );
    cityEntry.CityName:SetColor( frontColor );

    cityEntry.TradingPostIcon:SetColor( frontColor );

    -- Update Trading Post Icon
    if city:GetTrade():HasActiveTradingPost(m_originCity:GetOwner()) then
        cityEntry.TradingPostIcon:SetHide(false);
    else
        cityEntry.TradingPostIcon:SetHide(true);
    end

    -- Update City-State Quest Icon
    cityEntry.CityStateQuestIcon:SetHide(true);
    local questsManager : table = Game.GetQuestsManager();
    local questTooltip  : string = Locale.Lookup("LOC_CITY_STATES_QUESTS");
    if (questsManager ~= nil and Game.GetLocalPlayer() ~= nil) then
        local tradeRouteQuestInfo:table = GameInfo.Quests["QUEST_SEND_TRADE_ROUTE"];
        if (tradeRouteQuestInfo ~= nil) then
            if (questsManager:HasActiveQuestFromPlayer(Game.GetLocalPlayer(), city:GetOwner(), tradeRouteQuestInfo.Index)) then
                questTooltip = questTooltip .. "[NEWLINE]" .. tradeRouteQuestInfo.IconString .. questsManager:GetActiveQuestName(Game.GetLocalPlayer(), city:GetOwner(), tradeRouteQuestInfo.Index);
                cityEntry.CityStateQuestIcon:SetHide(false);
                cityEntry.CityStateQuestIcon:SetToolTipString(questTooltip);
            end
        end
    end

    -- Update turns to complete route
    local tradeRoute = {
        OriginCityPlayer        = m_originCity:GetOwner(),
        OriginCityID            = m_originCity:GetID(),
        DestinationCityPlayer   = city:GetOwner(),
        DestinationCityID       = city:GetID()
    };
    local tradePathLength, tripsToDestination, turnsToCompleteRoute = GetRouteInfo(tradeRoute);
    local tooltipString = ( "Total amount of[ICON_Turn]to complete this trade route[NEWLINE]" ..
                            "--------------------------------------------------------[NEWLINE]" ..
                            "Trade Route[ICON_Movement]: " .. tradePathLength .. "[NEWLINE]" ..
                            "Trips to destination: " .. tripsToDestination .. "[NEWLINE]" ..
                            "If started, route will complete in[ICON_Turn]: " .. Game.GetCurrentGameTurn() + turnsToCompleteRoute);

    cityEntry.TurnsToComplete:SetText(turnsToCompleteRoute);
    cityEntry.TurnsToComplete:SetToolTipString( tooltipString );
    cityEntry.TurnsToComplete:SetColor( frontColor );

    -- Setup resources
    local tooltipText = "";
    cityEntry.ResourceList:DestroyAllChildren();
    for yieldInfo in GameInfo.Yields() do
        local yieldValue, sourceText = GetYieldForCity(yieldInfo.Index, city, true);
        if (yieldValue > 0 ) or alignTradeRouteYields then
            if (tooltipText ~= "" and yieldValue > 0) then
                tooltipText = tooltipText .. "[NEWLINE]";
            end
            tooltipText = tooltipText .. sourceText;
            AddResourceEntry(yieldInfo, yieldValue, sourceText, cityEntry.ResourceList);
        end
    end
    cityEntry.Button:SetToolTipString(tooltipText);

    -- Setup callback
    cityEntry.Button:SetVoids(city:GetOwner(), city:GetID());
    cityEntry.Button:RegisterCallback( Mouse.eLClick, OnTradeRouteSelected );

    -- Process Anchoring
    cityEntry.ResourceList:ReprocessAnchoring();
end

function AddResourceEntry(yieldInfo:table, yieldValue:number, sourceText:string, stackControl:table, customOffset)
    local entryInstance:table = {};
    ContextPtr:BuildInstanceForControl( "ResourceEntryInstance", entryInstance, stackControl );

    local icon:string, text:string = FormatYieldText(yieldInfo, yieldValue);
    if yieldValue > 0 then
        entryInstance.ResourceEntryIcon:SetText(icon);
        entryInstance.ResourceEntryText:SetText(text);

        if (customOffset) then
            entryInstance.ResourceEntryIcon:SetOffsetX(customOffset);
            entryInstance.ResourceEntryText:SetOffsetX(customOffset);
        end

        -- Update text Color
        if (yieldInfo.YieldType == "YIELD_FOOD") then
            entryInstance.ResourceEntryText:SetColorByName("ResFoodLabelCS");
        elseif (yieldInfo.YieldType == "YIELD_PRODUCTION") then
            entryInstance.ResourceEntryText:SetColorByName("ResProductionLabelCS");
        elseif (yieldInfo.YieldType == "YIELD_GOLD") then
            entryInstance.ResourceEntryText:SetColorByName("ResGoldLabelCS");
        elseif (yieldInfo.YieldType == "YIELD_SCIENCE") then
            entryInstance.ResourceEntryText:SetColorByName("ResScienceLabelCS");
        elseif (yieldInfo.YieldType == "YIELD_CULTURE") then
            entryInstance.ResourceEntryText:SetColorByName("ResCultureLabelCS");
        elseif (yieldInfo.YieldType == "YIELD_FAITH") then
            entryInstance.ResourceEntryText:SetColorByName("ResFaithLabelCS");
        end
    else
        entryInstance.ResourceEntryIcon:SetHide(true);
        entryInstance.ResourceEntryText:SetHide(true);
    end
end

-- ===========================================================================
--  Filter functions
-- ===========================================================================

function RefreshFilters()
    local tradeManager:table = Game.GetTradeManager();

    -- Clear entries
    Controls.DestinationFilterPulldown:ClearEntries();
    m_filterList = {};
    m_filterCount = 0;

    -- Add All Filter
    AddFilter(Locale.Lookup("LOC_ROUTECHOOSER_FILTER_ALL"), nil);

    -- Add "International Routes" Filter
    AddFilter(Locale.Lookup("LOC_TRADE_FILTER_INTERNATIONAL_ROUTES_TEXT") , FilterByInternational);

    -- Add "City States with Trade Quest" Filter
    AddFilter(Locale.Lookup("LOC_TRADE_FILTER_CS_WITH_QUEST_TOOLTIP"), FilterByCityStatesWithTradeQuest);

    -- Add Filters by Civ
    for index, city in ipairs(m_unfilteredDestinations) do
        if not IsCityState(Players[city:GetOwner()]) then
            local playerConfig:table = PlayerConfigurations[city:GetOwner()];
            local name = Locale.Lookup(GameInfo.Civilizations[playerConfig:GetCivilizationTypeID()].Name);
            AddFilter(name, function() FilterByCiv(playerConfig:GetCivilizationTypeID()) end);
        end
    end

    -- Add City State Filter
    for index, city in ipairs(m_unfilteredDestinations) do
        local pPlayerInfluence:table = Players[city:GetOwner()]:GetInfluence();
        if pPlayerInfluence:CanReceiveInfluence() then
            -- If the city's owner can receive influence then it is a city state so add the city state filter
            AddFilter(Locale.Lookup("LOC_ROUTECHOOSER_FILTER_CITYSTATES"), FilterByCityStates);
            break;
        end
    end

    --[[
        -- Add Filters by Resource
        for index, city in ipairs(m_unfilteredDestinations) do
            for yieldInfo in GameInfo.Yields() do
                local yieldValue = GetYieldForCity(yieldInfo.Index, city, true);

                if (yieldValue ~= 0 ) then
                    AddFilter(Locale.Lookup(yieldInfo.Name), function() FilterByResource(yieldInfo.Index) end);
                end
            end
        end
    --]]

    -- Add filters to pulldown
    for index, filter in ipairs(m_filterList) do
        AddFilterEntry(index);
    end

    -- Select first filter
    Controls.FilterButton:SetText(m_filterList[m_filterSelected].FilterText);

    -- Calculate Internals
    Controls.DestinationFilterPulldown:CalculateInternals();

    UpdateFilterArrow();
end

function AddFilter(filterName:string, filterFunction)
    -- Make sure we don't add duplicate filters
    for index, filter in ipairs(m_filterList) do
        if filter.FilterText == filterName then
            return;
        end
    end

    m_filterCount = m_filterCount + 1;
    m_filterList[m_filterCount] = {FilterText=filterName, FilterFunction=filterFunction};
end

function AddFilterEntry(filterIndex:number)
    local filterEntry:table = {};
    Controls.DestinationFilterPulldown:BuildEntry( "FilterEntry", filterEntry );
    filterEntry.Button:SetText(m_filterList[filterIndex].FilterText);
    filterEntry.Button:SetVoids(i, filterIndex);
end

function OnFilterSelected(index:number, filterIndex:number)
    m_filterSelected = filterIndex;
    Controls.FilterButton:SetText(m_filterList[m_filterSelected].FilterText);

    Refresh();
end

function FilterByInternational()
    -- Clear Filter
    m_filteredDestinations = {};

    -- Filter by Yield Index
    for index, city in ipairs(m_unfilteredDestinations) do
        local player:table = Players[city:GetOwner()];

        if player:GetID() ~= Game.GetLocalPlayer() then
            table.insert(m_filteredDestinations, city);
        end
    end
end

function FilterByCiv(civTypeID:number)
    -- Clear Filter
    m_filteredDestinations = {};

    -- Filter by Civ Type ID
    for index, city in ipairs(m_unfilteredDestinations) do
        local playerConfig:table = PlayerConfigurations[city:GetOwner()];
        if playerConfig:GetCivilizationTypeID() == civTypeID then
            table.insert(m_filteredDestinations, city);
        end
    end
end

function FilterByResource(yieldIndex:number)
    -- Clear Filter
    m_filteredDestinations = {};

    -- Filter by Yield Index
    for index, city in ipairs(m_unfilteredDestinations) do
        local yieldValue = GetYieldForCity(yieldIndex, city, true);

        if (yieldValue ~= 0 ) then
            table.insert(m_filteredDestinations, city);
        end
    end
end

function FilterByCityStates()
    -- Clear Filter
    m_filteredDestinations = {};

    -- Filter only cities which aren't full civs meaning they're city-states
    for index, city in ipairs(m_unfilteredDestinations) do
        local playerConfig:table = PlayerConfigurations[city:GetOwner()];
        if playerConfig:GetCivilizationLevelTypeID() ~= CivilizationLevelTypes.CIVILIZATION_LEVEL_FULL_CIV then
            table.insert(m_filteredDestinations, city);
        end
    end
end

function FilterByCityStatesWithTradeQuest()
    -- Clear Filter
    m_filteredDestinations = {};

    -- Filter only cities which aren't full civs meaning they're city-states
    for index, city in ipairs(m_unfilteredDestinations) do
        local player:table = Players[city:GetOwner()];

        if (IsCityStateWithTradeQuest( player )) then
            table.insert(m_filteredDestinations, city);
        end
    end
end

-- ===========================================================================
--  Sort bar functions
-- ===========================================================================

-- Hides all the ascending/descending arrows
function ResetSortBar()
    Controls.FoodDescArrow:SetHide(true);
    Controls.ProductionDescArrow:SetHide(true);
    Controls.GoldDescArrow:SetHide(true);
    Controls.ScienceDescArrow:SetHide(true);
    Controls.CultureDescArrow:SetHide(true);
    Controls.FaithDescArrow:SetHide(true);
    Controls.TurnsToCompleteDescArrow:SetHide(true);

    Controls.FoodAscArrow:SetHide(true);
    Controls.ProductionAscArrow:SetHide(true);
    Controls.GoldAscArrow:SetHide(true);
    Controls.ScienceAscArrow:SetHide(true);
    Controls.CultureAscArrow:SetHide(true);
    Controls.FaithAscArrow:SetHide(true);
    Controls.TurnsToCompleteAscArrow:SetHide(true);
end

function RefreshSortBar()
    RefreshSortButtons( m_SortBySettings );

    if showSortOrdersPermanently or m_shiftDown then
        -- Hide the order texts
        HideSortOrderLabels();
        -- Show them based on current settings
        ShowSortOrderLabels();
    end
end

function ShowSortOrderLabels()
    -- Refresh and show sort orders
    RefreshSortOrderLabels( m_SortBySettings );
end

function HideSortOrderLabels()
    Controls.FoodSortOrder:SetHide(true);
    Controls.ProductionSortOrder:SetHide(true);
    Controls.GoldSortOrder:SetHide(true);
    Controls.ScienceSortOrder:SetHide(true);
    Controls.CultureSortOrder:SetHide(true);
    Controls.FaithSortOrder:SetHide(true);
    Controls.TurnsToCompleteSortOrder:SetHide(true);
end

-- Shows and hides arrows based on the passed sort order
function SetSortArrow( ascArrow:table, descArrow:table, sortOrder:number )
    if sortOrder == SORT_ASCENDING then
        descArrow:SetHide(true);
        ascArrow:SetHide(false);
    else
        descArrow:SetHide(false);
        ascArrow:SetHide(true);
    end
end

function RefreshSortButtons( sortSettings:table )
    -- Hide all arrows
    ResetSortBar();

    -- Set disabled color
    Controls.FoodSortButton:SetColorByName("ButtonDisabledCS");
    Controls.ProductionSortButton:SetColorByName("ButtonDisabledCS");
    Controls.GoldSortButton:SetColorByName("ButtonDisabledCS");
    Controls.ScienceSortButton:SetColorByName("ButtonDisabledCS");
    Controls.CultureSortButton:SetColorByName("ButtonDisabledCS");
    Controls.FaithSortButton:SetColorByName("ButtonDisabledCS");
    Controls.TurnsToCompleteSortButton:SetColorByName("ButtonDisabledCS");

    -- Go through settings and display arrows
    for index, sortEntry in ipairs(sortSettings) do
        if sortEntry.SortByID == SORT_BY_ID.FOOD then
            SetSortArrow(Controls.FoodAscArrow, Controls.FoodDescArrow, sortEntry.SortOrder)
            Controls.FoodSortButton:SetColorByName("ButtonCS");
        elseif sortEntry.SortByID == SORT_BY_ID.PRODUCTION then
            SetSortArrow(Controls.ProductionAscArrow, Controls.ProductionDescArrow, sortEntry.SortOrder)
            Controls.ProductionSortButton:SetColorByName("ButtonCS");
        elseif sortEntry.SortByID == SORT_BY_ID.GOLD then
            SetSortArrow(Controls.GoldAscArrow, Controls.GoldDescArrow, sortEntry.SortOrder)
            Controls.GoldSortButton:SetColorByName("ButtonCS");
        elseif sortEntry.SortByID == SORT_BY_ID.SCIENCE then
            SetSortArrow(Controls.ScienceAscArrow, Controls.ScienceDescArrow, sortEntry.SortOrder)
            Controls.ScienceSortButton:SetColorByName("ButtonCS");
        elseif sortEntry.SortByID == SORT_BY_ID.CULTURE then
            SetSortArrow(Controls.CultureAscArrow, Controls.CultureDescArrow, sortEntry.SortOrder)
            Controls.CultureSortButton:SetColorByName("ButtonCS");
        elseif sortEntry.SortByID == SORT_BY_ID.FAITH then
            SetSortArrow(Controls.FaithAscArrow, Controls.FaithDescArrow, sortEntry.SortOrder)
            Controls.FaithSortButton:SetColorByName("ButtonCS");
        elseif sortEntry.SortByID == SORT_BY_ID.TURNS_TO_COMPLETE then
            SetSortArrow(Controls.TurnsToCompleteAscArrow, Controls.TurnsToCompleteDescArrow, sortEntry.SortOrder)
            Controls.TurnsToCompleteSortButton:SetColorByName("ButtonCS");
        end
    end
end

function RefreshSortOrderLabels( sortSettings:table )
    for index, sortEntry in ipairs(sortSettings) do
        if sortEntry.SortByID == SORT_BY_ID.FOOD then
            Controls.FoodSortOrder:SetHide(false);
            Controls.FoodSortOrder:SetText(index);
            Controls.FoodSortOrder:SetColorByName("ResFoodLabelCS");
        elseif sortEntry.SortByID == SORT_BY_ID.PRODUCTION then
            Controls.ProductionSortOrder:SetHide(false);
            Controls.ProductionSortOrder:SetText(index);
            Controls.ProductionSortOrder:SetColorByName("ResProductionLabelCS");
        elseif sortEntry.SortByID == SORT_BY_ID.GOLD then
            Controls.GoldSortOrder:SetHide(false);
            Controls.GoldSortOrder:SetText(index);
            Controls.GoldSortOrder:SetColorByName("ResGoldLabelCS");
        elseif sortEntry.SortByID == SORT_BY_ID.SCIENCE then
            Controls.ScienceSortOrder:SetHide(false);
            Controls.ScienceSortOrder:SetText(index);
            Controls.ScienceSortOrder:SetColorByName("ResScienceLabelCS");
        elseif sortEntry.SortByID == SORT_BY_ID.CULTURE then
            Controls.CultureSortOrder:SetHide(false);
            Controls.CultureSortOrder:SetText(index);
            Controls.CultureSortOrder:SetColorByName("ResCultureLabelCS");
        elseif sortEntry.SortByID == SORT_BY_ID.FAITH then
            Controls.FaithSortOrder:SetHide(false);
            Controls.FaithSortOrder:SetText(index);
            Controls.FaithSortOrder:SetColorByName("ResFaithLabelCS");
        elseif sortEntry.SortByID == SORT_BY_ID.TURNS_TO_COMPLETE then
            Controls.TurnsToCompleteSortOrder:SetHide(false);
            Controls.TurnsToCompleteSortOrder:SetText(index);
        end
    end
end

-- ===========================================================================
--  General Helper functions
-- ===========================================================================

-- Checks if the player is a civ, other than the local player
function IsOtherCiv( player:table )
    if player:GetID() ~= Game.GetLocalPlayer() then
        return true
    end

    return false
end

function IsCityState( player:table )
    local playerInfluence:table = player:GetInfluence();
    if  playerInfluence:CanReceiveInfluence() then
        return true
    end

    return false
end

function IsCityStateWithTradeQuest( player:table )
    local questsManager : table = Game.GetQuestsManager();
    local questTooltip  : string = Locale.Lookup("LOC_CITY_STATES_QUESTS");
    if (questsManager ~= nil and Game.GetLocalPlayer() ~= nil) then
        local tradeRouteQuestInfo:table = GameInfo.Quests["QUEST_SEND_TRADE_ROUTE"];
        if (tradeRouteQuestInfo ~= nil) then
            if (questsManager:HasActiveQuestFromPlayer(Game.GetLocalPlayer(), player:GetID(), tradeRouteQuestInfo.Index)) then
                return true
            end
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Trade route helper functions
-- ---------------------------------------------------------------------------

function TradeRouteSelected( cityOwner:number, cityID:number )
    local player:table = Players[cityOwner];
    if player then
        local pCity:table = player:GetCities():FindID(cityID);
        if pCity then
            m_destinationCity = pCity;
        else
            error("Unable to find city '"..tostring(cityID).."' for creating a trade route.");
        end
    end

    Refresh();
end

function GetYieldForCity(yieldIndex:number, city:table, originCity:boolean)
    local tradeManager = Game.GetTradeManager();
    local yieldInfo = GameInfo.Yields[yieldIndex];
    local totalValue = 0;
    local partialValue = 0;
    local sourceText = "";

    -- From route
    if (originCity) then
        partialValue = tradeManager:CalculateOriginYieldFromPotentialRoute(m_originCity:GetOwner(), m_originCity:GetID(), city:GetOwner(), city:GetID(), yieldIndex);
    else
        partialValue = tradeManager:CalculateDestinationYieldFromPotentialRoute(m_originCity:GetOwner(), m_originCity:GetID(), city:GetOwner(), city:GetID(), yieldIndex);
    end
    totalValue = totalValue + partialValue;
    if (partialValue > 0 and yieldInfo ~= nil) then
        if (sourceText ~= "") then
            sourceText = sourceText .. "[NEWLINE]";
        end
        sourceText = sourceText .. Locale.Lookup("LOC_ROUTECHOOSER_YIELD_SOURCE_DISTRICTS", partialValue, yieldInfo.IconString, yieldInfo.Name, city:GetName());
    end
    -- From path
    if (originCity) then
        partialValue = tradeManager:CalculateOriginYieldFromPath(m_originCity:GetOwner(), m_originCity:GetID(), city:GetOwner(), city:GetID(), yieldIndex);
    else
        partialValue = tradeManager:CalculateDestinationYieldFromPath(m_originCity:GetOwner(), m_originCity:GetID(), city:GetOwner(), city:GetID(), yieldIndex);
    end
    totalValue = totalValue + partialValue;
    if (partialValue > 0 and yieldInfo ~= nil) then
        if (sourceText ~= "") then
            sourceText = sourceText .. "[NEWLINE]";
        end
        sourceText = sourceText .. Locale.Lookup("LOC_ROUTECHOOSER_YIELD_SOURCE_TRADING_POSTS", partialValue, yieldInfo.IconString, yieldInfo.Name);
    end
    -- From modifiers
    local resourceID = -1;
    if (originCity) then
        partialValue = tradeManager:CalculateOriginYieldFromModifiers(m_originCity:GetOwner(), m_originCity:GetID(), city:GetOwner(), city:GetID(), yieldIndex, resourceID);
    else
        partialValue = tradeManager:CalculateDestinationYieldFromModifiers(m_originCity:GetOwner(), m_originCity:GetID(), city:GetOwner(), city:GetID(), yieldIndex, resourceID);
    end
    totalValue = totalValue + partialValue;
    if (partialValue > 0 and yieldInfo ~= nil) then
        if (sourceText ~= "") then
            sourceText = sourceText .. "[NEWLINE]";
        end
        sourceText = sourceText .. Locale.Lookup("LOC_ROUTECHOOSER_YIELD_SOURCE_BONUSES", partialValue, yieldInfo.IconString, yieldInfo.Name);
    end

    return totalValue, sourceText;
end

-- ===========================================================================
--  Look at the plot of the destination city.
--  Not always done when selected, as sometimes the TradeOverview will be
--  open and it's going to perform it's own lookat.
-- ===========================================================================
function RealizeLookAtDestinationCity()
    if m_destinationCity == nil then
        UI.DataError("TradeRouteChooser cannot look at a NIL destination.");
        return;
    end

    local locX      :number = m_destinationCity:GetX();
    local locY      :number = m_destinationCity:GetY();
    local screenXOff:number = 0.6;

    -- Change offset if the TradeOveriew (exists and) is open as well.
    if m_pTradeOverviewContext and (not m_pTradeOverviewContext:IsHidden()) then
        screenXOff = 0.42;
    end

    UI.LookAtPlotScreenPosition( locX, locY, screenXOff, 0.5 ); -- Look at 60% over from left side of screen
end

-- ===========================================================================
--  UI Button Callback
-- ===========================================================================
function OnTradeRouteSelected( cityOwner:number, cityID:number )
    TradeRouteSelected( cityOwner, cityID );
    RealizeLookAtDestinationCity();

    LuaEvents.TradeRouteChooser_RouteConsidered();
end

function OnRepeatRouteCheckbox()
    if not Controls.RepeatRouteCheckbox:IsChecked() then
        Controls.FromTopSortEntryCheckbox:SetCheck(false);
    end
end

function OnFromTopSortEntryCheckbox()
    -- FromTopSortEntryCheckbox is tied to RepeatRouteCheckbox
    if Controls.FromTopSortEntryCheckbox:IsChecked() then
        Controls.RepeatRouteCheckbox:SetCheck(true);
    end
end

function RequestTradeRoute()
    local selectedUnit = UI.GetHeadSelectedUnit();
    if m_destinationCity and selectedUnit then
        local operationParams = {};
        operationParams[UnitOperationTypes.PARAM_X0] = m_destinationCity:GetX();
        operationParams[UnitOperationTypes.PARAM_Y0] = m_destinationCity:GetY();
        operationParams[UnitOperationTypes.PARAM_X1] = selectedUnit:GetX();
        operationParams[UnitOperationTypes.PARAM_Y1] = selectedUnit:GetY();
        if (UnitManager.CanStartOperation(selectedUnit, UnitOperationTypes.MAKE_TRADE_ROUTE, nil, operationParams)) then
            UnitManager.RequestOperation(selectedUnit, UnitOperationTypes.MAKE_TRADE_ROUTE, operationParams);
            UI.SetInterfaceMode(InterfaceModeTypes.SELECTION);
            UI.PlaySound("START_TRADE_ROUTE");

            -- Automated Handlers
            if Controls.RepeatRouteCheckbox:IsChecked() and Controls.FromTopSortEntryCheckbox:IsChecked() then
                AutomateTrader(selectedUnit:GetID(), true, m_SortBySettings);
            elseif Controls.RepeatRouteCheckbox:IsChecked() then
                AutomateTrader(selectedUnit:GetID(), true);
            else
                AutomateTrader(selectedUnit:GetID(), false);
            end
        end

        return true;
    end

    return false;
end

function UpdateFilterArrow()
    if Controls.DestinationFilterPulldown:IsOpen() then
        Controls.PulldownOpenedArrow:SetHide(true);
        Controls.PulldownClosedArrow:SetHide(false);
    else
        Controls.PulldownOpenedArrow:SetHide(false);
        Controls.PulldownClosedArrow:SetHide(true);
    end
end

-- ---------------------------------------------------------------------------
-- Sort bar insert buttons
-- ---------------------------------------------------------------------------
function OnSortByFood()
    -- If shift is not being pressed, reset sort settings
    if not m_shiftDown then
        m_SortBySettings = {};
    end

    -- Sort based on currently showing icon toggled
    if Controls.FoodDescArrow:IsHidden() then
        InsertSortEntry(SORT_BY_ID.FOOD, SORT_DESCENDING, m_SortBySettings);
    else
        InsertSortEntry(SORT_BY_ID.FOOD, SORT_ASCENDING, m_SortBySettings);
    end

    Refresh();
end

function OnSortByProduction()
    -- If shift is not being pressed, reset sort settings
    if not m_shiftDown then
        m_SortBySettings = {};
    end

    -- Sort based on currently showing icon toggled
    if Controls.ProductionDescArrow:IsHidden() then
        InsertSortEntry(SORT_BY_ID.PRODUCTION, SORT_DESCENDING, m_SortBySettings);
    else
        InsertSortEntry(SORT_BY_ID.PRODUCTION, SORT_ASCENDING, m_SortBySettings);
    end

    Refresh();
end

function OnSortByGold()
    -- If shift is not being pressed, reset sort settings
    if not m_shiftDown then
        m_SortBySettings = {};
    end

    -- Sort based on currently showing icon toggled
    if Controls.GoldDescArrow:IsHidden() then
        InsertSortEntry(SORT_BY_ID.GOLD, SORT_DESCENDING, m_SortBySettings);
    else
        InsertSortEntry(SORT_BY_ID.GOLD, SORT_ASCENDING, m_SortBySettings);
    end

    Refresh();
end

function OnSortByScience()
    -- If shift is not being pressed, reset sort settings
    if not m_shiftDown then
        m_SortBySettings = {};
    end

    -- Sort based on currently showing icon toggled
    if Controls.ScienceDescArrow:IsHidden() then
        InsertSortEntry(SORT_BY_ID.SCIENCE, SORT_DESCENDING, m_SortBySettings);
    else
        InsertSortEntry(SORT_BY_ID.SCIENCE, SORT_ASCENDING, m_SortBySettings);
    end

    Refresh();
end

function OnSortByCulture()
    -- If shift is not being pressed, reset sort settings
    if not m_shiftDown then
        m_SortBySettings = {};
    end

    -- Sort based on currently showing icon toggled
    if Controls.CultureDescArrow:IsHidden() then
        InsertSortEntry(SORT_BY_ID.CULTURE, SORT_DESCENDING, m_SortBySettings);
    else
        InsertSortEntry(SORT_BY_ID.CULTURE, SORT_ASCENDING, m_SortBySettings);
    end

    Refresh();
end

function OnSortByFaith()
    -- If shift is not being pressed, reset sort settings
    if not m_shiftDown then
        m_SortBySettings = {};
    end

    -- Sort based on currently showing icon toggled
    if Controls.FaithDescArrow:IsHidden() then
        InsertSortEntry(SORT_BY_ID.FAITH, SORT_DESCENDING, m_SortBySettings);
    else
        InsertSortEntry(SORT_BY_ID.FAITH, SORT_ASCENDING, m_SortBySettings);
    end

    Refresh();
end

function OnSortByTurnsToComplete()
    -- If shift is not being pressed, reset sort settings
    if not m_shiftDown then
        m_SortBySettings = {};
    end

    -- Sort based on currently showing icon toggled
    if Controls.TurnsToCompleteDescArrow:IsHidden() then
        InsertSortEntry(SORT_BY_ID.TURNS_TO_COMPLETE, SORT_DESCENDING, m_SortBySettings);
    else
        InsertSortEntry(SORT_BY_ID.TURNS_TO_COMPLETE, SORT_ASCENDING, m_SortBySettings);
    end

    Refresh();
end

-- ---------------------------------------------------------------------------
-- Sort bar delete buttons
-- ---------------------------------------------------------------------------
function OnNotSortByFood()
    RemoveSortEntry( SORT_BY_ID.FOOD, m_SortBySettings);

    Refresh();
end

function OnNotSortByProduction()
    RemoveSortEntry( SORT_BY_ID.PRODUCTION, m_SortBySettings);

    Refresh();
end

function OnNotSortByGold()
    RemoveSortEntry( SORT_BY_ID.GOLD, m_SortBySettings);

    Refresh();
end

function OnNotSortByScience()
    RemoveSortEntry( SORT_BY_ID.SCIENCE, m_SortBySettings);

    Refresh();
end

function OnNotSortByCulture()
    RemoveSortEntry( SORT_BY_ID.CULTURE, m_SortBySettings);

    Refresh();
end

function OnNotSortByFaith()
    RemoveSortEntry( SORT_BY_ID.FAITH, m_SortBySettings);

    Refresh();
end

function OnNotSortByTurnsToComplete()
    RemoveSortEntry( SORT_BY_ID.TURNS_TO_COMPLETE, m_SortBySettings);

    Refresh();
end

-- ===========================================================================
--  Rise/Hide and refresh Trade UI
-- ===========================================================================
function OnInterfaceModeChanged( oldMode:number, newMode:number )
    if (oldMode == InterfaceModeTypes.MAKE_TRADE_ROUTE) then
        Close();
    end
    if (newMode == InterfaceModeTypes.MAKE_TRADE_ROUTE) then
        Open();
    end
end

function OnClose()
    Close();

    if UI.GetInterfaceMode() == InterfaceModeTypes.MAKE_TRADE_ROUTE then
        UI.SetInterfaceMode(InterfaceModeTypes.SELECTION);
    end
end

function Close()
    LuaEvents.TradeRouteChooser_SetTradeUnitStatus("");

    ContextPtr:SetHide(true);

    LuaEvents.TradeRouteChooser_Close();

    if UILens.IsLensActive("TradeRoute") then
        -- Make sure to switch back to default lens
        UILens.SetActive("Default");
    end
end

function Open()
    LuaEvents.TradeRouteChooser_SetTradeUnitStatus("LOC_HUD_UNIT_PANEL_CHOOSING_TRADE_ROUTE");

    ContextPtr:SetHide(false);
    m_destinationCity = nil;
    Controls.RepeatRouteCheckbox:SetCheck(false);
    Controls.FromTopSortEntryCheckbox:SetCheck(false);

    -- Play Open Animation
    Controls.RouteChooserSlideAnim:SetToBeginning();
    Controls.RouteChooserSlideAnim:Play();

    -- Switch to TradeRoute Lens
    UILens.SetActive("TradeRoute");

    if m_postOpenSelectPlayerID ~= -1 then
        TradeRouteSelected( m_postOpenSelectPlayerID, m_postOpenSelectCityID );
        RealizeLookAtDestinationCity();

        -- Reset values
        m_postOpenSelectPlayerID = -1;
        m_postOpenSelectCityID = -1;
    end

    LuaEvents.TradeRouteChooser_Open();

    local selectedUnit:table = UI.GetHeadSelectedUnit();
    local selectedUnitID:number = selectedUnit:GetID();

    local lastRoute:table = GetLastRouteForTrader(selectedUnitID);

    if lastRoute ~= nil then
        print("Last route for trader " .. selectedUnitID .. ": " .. GetTradeRouteString(lastRoute));
        originCity = Cities.GetCityInPlot(selectedUnit:GetX(), selectedUnit:GetY());

        if IsRoutePossible(originCity:GetOwner(), originCity:GetID(), lastRoute.DestinationCityPlayer, DestinationCityID) then
            local destinationPlayer:table = Players[lastRoute.DestinationCityPlayer];
            m_destinationCity = destinationPlayer:GetCities():FindID(lastRoute.DestinationCityID);
        else
            print("Route is no longer valid.");
        end
    else
        print("No last route was found for trader " .. selectedUnitID);
    end

    Refresh();
end

function CheckNeedsToOpen()
    local selectedUnit:table = UI.GetHeadSelectedUnit();
    if selectedUnit ~= nil then
        local selectedUnitInfo:table = GameInfo.Units[selectedUnit:GetUnitType()];
        if selectedUnitInfo ~= nil and selectedUnitInfo.MakeTradeRoute == true then
            local activityType:number = UnitManager.GetActivityType(selectedUnit);
            if activityType == ActivityTypes.ACTIVITY_AWAKE and selectedUnit:GetMovesRemaining() > 0 then
                -- If we're open and this is a trade unit then just refresh
                if not ContextPtr:IsHidden() then
                    Refresh();
                else
                    UI.SetInterfaceMode(InterfaceModeTypes.MAKE_TRADE_ROUTE);
                end

                -- Early out so we don't call Close()
                return;
            end
        end
    end

    -- If we're open and this unit is not a trade unit then close
    if not ContextPtr:IsHidden() then
        Close();
    end
end

-- ===========================================================================
--  UI Events
-- ===========================================================================
function OnInit( isReload:boolean )
    if isReload then
        LuaEvents.GameDebug_GetValues( "TradeRouteChooser" );
    end
end

function OnShutdown()
    -- Cache values for hotloading...
    LuaEvents.GameDebug_AddValue("TradeRouteChooser", "filterIndex", m_filterSelected );
    LuaEvents.GameDebug_AddValue("TradeRouteChooser", "destinationCity", m_destinationCity );
end

-- ===========================================================================
--  LUA Event
--  Set cached values back after a hotload.
-- ===========================================================================s
function OnGameDebugReturn( context:string, contextTable:table )
    if context ~= "TradeRouteChooser" then
        return;
    end

    m_filterSelected = contextTable["filterIndex"];
    m_destinationCity = contextTable["destinationCity"];

    Refresh();
end

-- ===========================================================================
--  GAME Event
--  City was selected so close route chooser
-- ===========================================================================
function OnCitySelectionChanged(owner, ID, i, j, k, bSelected, bEditable)
    if not ContextPtr:IsHidden() and owner == Game.GetLocalPlayer() then
        OnClose();
    end
end

-- ===========================================================================
--  GAME Event
--  Unit was selected so close route chooser
-- ===========================================================================
function OnUnitSelectionChanged( playerID : number, unitID : number, hexI : number, hexJ : number, hexK : number, bSelected : boolean, bEditable : boolean )

    -- Make sure we're the local player and not observing
    if playerID ~= Game.GetLocalPlayer() or playerID == -1 then
        return;
    end

    -- If this is a de-selection event then close
    if not bSelected then
        OnClose();
        return;
    end

    -- Only open if TradeOverview is hidden
    if m_pTradeOverviewContext == nil or m_pTradeOverviewContext:IsHidden() then
        CheckNeedsToOpen();
    else
        print("Trade Overview was open. Not auto opening trade panel.")
    end
end

function OnLocalPlayerTurnEnd()
    if(GameConfiguration.IsHotseat()) then
        OnClose();
    end
end

function OnUnitActivityChanged( playerID :number, unitID :number, eActivityType :number)
    -- Make sure we're the local player and not observing
    if playerID ~= Game.GetLocalPlayer() or playerID == -1 then
        return;
    end

    CheckNeedsToOpen();
end

function OnPolicyChanged( ePlayer )
    if not ContextPtr:IsHidden() and ePlayer == Game.GetLocalPlayer() then
        Refresh();
    end
end

-- ===========================================================================
--  Input
--  UI Event Handler
-- ===========================================================================
function KeyDownHandler( key:number )
    if key == Keys.VK_SHIFT then
        m_shiftDown = true;
        if not showSortOrdersPermanently then
            ShowSortOrderLabels();
        end
        -- let it fall through
    end
    return false;
end

function KeyUpHandler( key:number )
    if key == Keys.VK_SHIFT then
        m_shiftDown = false;
        if not showSortOrdersPermanently then
            HideSortOrderLabels();
        end
        -- let it fall through
    end
    if key == Keys.VK_RETURN then
        if m_destinationCity then
            RequestTradeRoute();
        end
        -- Dont let it fall through
        return true;
    end
    if key == Keys.VK_ESCAPE then
        OnClose();
        return true;
    end
    return false;
end

function OnInputHandler( pInputStruct:table )
    local uiMsg = pInputStruct:GetMessageType();
    if uiMsg == KeyEvents.KeyDown then return KeyDownHandler( pInputStruct:GetKey() ); end
    if uiMsg == KeyEvents.KeyUp then return KeyUpHandler( pInputStruct:GetKey() ); end
    return false;
end

-- ===========================================================================
function OnSelectRouteFromOverview( destinationOwnerID:number, destinationCityID:number )
    if not ContextPtr:IsHidden() then
        -- If we're already open then select the route
        TradeRouteSelected( destinationOwnerID, destinationCityID );
    else
        -- If we're not open then set the route to be selected after we open the panel
        m_postOpenSelectPlayerID = destinationOwnerID;
        m_postOpenSelectCityID = destinationCityID;

        -- Check to see if we need to open
        CheckNeedsToOpen();
    end
end

-- ===========================================================================
--  Setup
-- ===========================================================================
function Initialize()
    print("Initializing BTS Trade Route Chooser");

    TradeSupportAutomater_Initialize();

    -- Context Events
    ContextPtr:SetInitHandler( OnInit );
    ContextPtr:SetShutdown( OnShutdown );
    ContextPtr:SetInputHandler( OnInputHandler, true );

    -- Lua Events
    LuaEvents.GameDebug_Return.Add( OnGameDebugReturn );

    -- Context Events
    LuaEvents.TradeOverview_SelectRouteFromOverview.Add( OnSelectRouteFromOverview );

    -- Game Engine Events
    Events.InterfaceModeChanged.Add( OnInterfaceModeChanged );
    Events.CitySelectionChanged.Add( OnCitySelectionChanged );
    Events.UnitSelectionChanged.Add( OnUnitSelectionChanged );
    Events.UnitActivityChanged.Add( OnUnitActivityChanged );
    Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );
    Events.GovernmentPolicyChanged.Add( OnPolicyChanged );
    Events.GovernmentPolicyObsoleted.Add( OnPolicyChanged );

    -- Control Events
    Controls.BeginRouteButton:RegisterCallback( eLClick, RequestTradeRoute );
    Controls.BeginRouteButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    Controls.FilterButton:RegisterCallback( eLClick, UpdateFilterArrow );
    Controls.DestinationFilterPulldown:RegisterSelectionCallback( OnFilterSelected );
    Controls.Header_CloseButton:RegisterCallback( eLClick, OnClose );
    -- Control events - checkboxes
    Controls.RepeatRouteCheckbox:RegisterCallback( eLClick, OnRepeatRouteCheckbox );
    Controls.RepeatRouteCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    Controls.FromTopSortEntryCheckbox:RegisterCallback( eLClick, OnFromTopSortEntryCheckbox );
    Controls.FromTopSortEntryCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);


    -- Control events - sort bar
    Controls.FoodSortButton:RegisterCallback( Mouse.eLClick, OnSortByFood);
    Controls.FoodSortButton:RegisterCallback( Mouse.eRClick, OnNotSortByFood);
    Controls.FoodSortButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

    Controls.ProductionSortButton:RegisterCallback( Mouse.eLClick, OnSortByProduction);
    Controls.ProductionSortButton:RegisterCallback( Mouse.eRClick, OnNotSortByProduction);
    Controls.ProductionSortButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

    Controls.GoldSortButton:RegisterCallback( Mouse.eLClick, OnSortByGold);
    Controls.GoldSortButton:RegisterCallback( Mouse.eRClick, OnNotSortByGold);
    Controls.GoldSortButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

    Controls.ScienceSortButton:RegisterCallback( Mouse.eLClick, OnSortByScience);
    Controls.ScienceSortButton:RegisterCallback( Mouse.eRClick, OnNotSortByScience);
    Controls.ScienceSortButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

    Controls.CultureSortButton:RegisterCallback( Mouse.eLClick, OnSortByCulture);
    Controls.CultureSortButton:RegisterCallback( Mouse.eRClick, OnNotSortByCulture);
    Controls.CultureSortButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

    Controls.FaithSortButton:RegisterCallback( Mouse.eLClick, OnSortByFaith);
    Controls.FaithSortButton:RegisterCallback( Mouse.eRClick, OnNotSortByFaith);
    Controls.FaithSortButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

    Controls.TurnsToCompleteSortButton:RegisterCallback( Mouse.eLClick, OnSortByTurnsToComplete);
    Controls.TurnsToCompleteSortButton:RegisterCallback( Mouse.eRClick, OnNotSortByTurnsToComplete);
    Controls.TurnsToCompleteSortButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);


    -- Obtain refrence to another context.
    m_pTradeOverviewContext = ContextPtr:LookUpControl("/InGame/TradeOverview");
end
Initialize();