-- ===========================================================================
--	Local Constants
-- ===========================================================================

local SORT_BY_ID:table = {
	FOOD = 1;
	PRODUCTION = 2;
	GOLD = 3;
	SCIENCE = 4;
	CULTURE = 5;
	FAITH = 6;
	TURNS_TO_COMPLETE = 7;
}

local SORT_ASCENDING = 1;
local SORT_DESCENDING = 2;

local CompareFunctionByID	= {};

CompareFunctionByID[SORT_BY_ID.FOOD]				= function(a, b) return CompareByFood(a, b) end;
CompareFunctionByID[SORT_BY_ID.PRODUCTION]			= function(a, b) return CompareByProduction(a, b) end;
CompareFunctionByID[SORT_BY_ID.GOLD]				= function(a, b) return CompareByGold(a, b) end;
CompareFunctionByID[SORT_BY_ID.SCIENCE]				= function(a, b) return CompareByScience(a, b) end;
CompareFunctionByID[SORT_BY_ID.CULTURE]				= function(a, b) return CompareByCulture(a, b) end;
CompareFunctionByID[SORT_BY_ID.FAITH]				= function(a, b) return CompareByFaith(a, b) end;
CompareFunctionByID[SORT_BY_ID.TURNS_TO_COMPLETE]	= function(a, b) return CompareByTurnsToComplete(a, b) end;

-- ===========================================================================
--	Variables
-- ===========================================================================

local m_LocalPlayerRunningRoutes	:table 	= {};	-- Tracks local players active routes
local m_TradersAutomatedSettings	:table	= {};	-- Tracks traders, and if they are automated

-- ===========================================================================
--	Constants Getter Functions
-- ===========================================================================

function GetSortByIdConstants()
	return SORT_BY_ID;
end

function GetSortAscendingIdConstant()
	return SORT_ASCENDING;
end

function GetSortDescendingIdConstant()
	return SORT_DESCENDING;
end

function GetCompareFunctionByID()
	return CompareFunctionByID
end

-- ===========================================================================
--	Trader Route tracker - Tracks active routes, turns remaining
-- ===========================================================================

function GetLocalPlayerRunningRoutes()
	CheckConsistencyWithMyRunningRoutes(m_LocalPlayerRunningRoutes);

	return m_LocalPlayerRunningRoutes;
end

function GetLastRouteForTrader( traderID:number )
	LoadTraderAutomatedInfo();

	if m_TradersAutomatedSettings[traderID] ~= nil then
		return m_TradersAutomatedSettings[traderID].LastRouteInfo;
	end
end

-- Adds the route turns remaining to the table, if it does not exist already
function AddRouteWithTurnsRemaining( routeInfo:table, routesTable:table, addedFromConsistencyCheck:boolean)
	-- print("Adding route: " .. GetTradeRouteString(routeInfo));

	local originPlayer:table = Players[routeInfo.OriginCityPlayer];
	local originCity:table = originPlayer:GetCities():FindID(routeInfo.OriginCityID);

	local destinationPlayer:table = Players[routeInfo.DestinationCityPlayer];
	local destinationCity:table = destinationPlayer:GetCities():FindID(routeInfo.DestinationCityID);

	local tradePathLength, tripsToDestination, turnsToCompleteRoute = GetRouteInfo( originCity, destinationCity );

	local routeIndex = findIndex ( routesTable, routeInfo, CheckRouteEquality );

	if routeIndex == -1 then
		-- Build entry
		local routeEntry:table = {
			OriginCityPlayer 		= routeInfo.OriginCityPlayer;
			OriginCityID 			= routeInfo.OriginCityID;
			DestinationCityPlayer 	= routeInfo.DestinationCityPlayer;
			DestinationCityID 		= routeInfo.DestinationCityID;
			TraderUnitID 			= routeInfo.TraderUnitID;
			TurnsRemaining 			= turnsToCompleteRoute;
		};

		-- Optional flag
		if addedFromConsistencyCheck ~= nil then
			routeEntry.AddedFromCheck = addedFromConsistencyCheck;
		end

		-- Append entry
		table.insert(routesTable, routeEntry);
		SaveRunningRoutesInfo();
	else
		print("AddRouteWithTurnsRemaining: Route already exists in table.");
	end
end

-- Decrements routes present. Removes those that completed
function UpdateRoutesWithTurnsRemaining( routesTable:table )
	-- Manually control the indices, so that you can iterate over the table while deleting items within it
	local i = 1;
	while i <= tableLength(routesTable) do
		if routesTable[i].TurnsRemaining ~= nil then
			routesTable[i].TurnsRemaining = routesTable[i].TurnsRemaining - 1;
			print("Updated route " .. GetTradeRouteString(routesTable[i]) .. " with turns remaining " .. routesTable[i].TurnsRemaining)
			
			if routesTable[i].TurnsRemaining <= 0 then
				print("Removing route: " .. GetTradeRouteString(routesTable[i]));
				table.remove(routesTable, i);
			else
				i = i + 1;
			end
		end
	end

	SaveRunningRoutesInfo();
end

-- Checks if routes running in game and the routesTable are consistent with each other
function CheckConsistencyWithMyRunningRoutes( routesTable:table )
	-- Build currently running routes
	local routesCurrentlyRunning:table = {};
	local localPlayerCities:table = Players[Game.GetLocalPlayer()]:GetCities();
	for i,city in localPlayerCities:Members() do
		local outgoingRoutes = city:GetTrade():GetOutgoingRoutes();
		for j, routeInfo in ipairs(outgoingRoutes) do
			table.insert(routesCurrentlyRunning, routeInfo);
		end
	end

	-- Add all routes in routesCurrentlyRunning table that are not in routesTable
	for i, route in ipairs(routesCurrentlyRunning) do
		local routeIndex = findIndex( routesTable, route, CheckRouteEquality );

		-- Is the route not present?
		if routeIndex == -1 then
			-- Add it to the list, and set the optional flag
			print(GetTradeRouteString(route) .. " was not present. Adding it to the table.");
			AddRouteWithTurnsRemaining( route, routesTable, true);
		end
	end

	-- Remove all routes in routesTable, that are not in routesCurrentlyRunning.
	-- Manually control the indices, so that you can iterate over the table while deleting items within it
	local i = 1;
	while i <= tableLength(routesTable) do
		local routeIndex = findIndex( routesCurrentlyRunning, routesTable[i], CheckRouteEquality );

		-- Is the route not present?
		if routeIndex == -1 then
			print("Route " .. GetTradeRouteString(routesTable[i]) .. " is no longer running. Removing it.");
			table.remove(routesTable, i)
		else
			i = i + 1
		end
	end

	SaveRunningRoutesInfo();
end

function SaveRunningRoutesInfo()
	-- Dump active routes info
	print("Saving running routes info in PlayerConfig database")
	local dataDump = DataDumper(m_LocalPlayerRunningRoutes, "localPlayerRunningRoutes", true);
	-- print(dataDump);
	PlayerConfigurations[Game.GetLocalPlayer()]:SetValue("BTS_LocalPlayerRunningRotues", dataDump);
end

function LoadRunningRoutesInfo()
	local localPlayerID = Game.GetLocalPlayer();
	if(PlayerConfigurations[localPlayerID]:GetValue("BTS_LocalPlayerRunningRotues") ~= nil) then
		print("Retrieving previous routes PlayerConfig database")
		local dataDump = PlayerConfigurations[localPlayerID]:GetValue("BTS_LocalPlayerRunningRotues");
		-- print(dataDump);
		loadstring(dataDump)();
		m_LocalPlayerRunningRoutes = localPlayerRunningRoutes;
	else
		print("No running route data was found, on load.")
	end

	-- Check for consistency
	CheckConsistencyWithMyRunningRoutes(m_LocalPlayerRunningRoutes);
end

-- ---------------------------------------------------------------------------
-- Game event hookups (Local to this file)
-- ---------------------------------------------------------------------------

local function TradeSupportTracker_OnUnitOperationStarted(ownerID:number, unitID:number, operationID:number)
	if ownerID == Game.GetLocalPlayer() and operationID == UnitOperationTypes.MAKE_TRADE_ROUTE then
		-- Unit was just started a trade route. Find the route, and update the tables
		local localPlayerCities:table = Players[ownerID]:GetCities();
		for i,city in localPlayerCities:Members() do
			local outgoingRoutes = city:GetTrade():GetOutgoingRoutes();
			for j,route in ipairs(outgoingRoutes) do
				if route.TraderUnitID == unitID then
					-- Add it to the local players runnning routes
					print("Route just started. Adding Route: " .. GetTradeRouteString(route));
					AddRouteWithTurnsRemaining( route, m_LocalPlayerRunningRoutes );
				end
			end
		end
	end
end

local function TradeSupportTracker_OnUnitOperationsCleared(ownerID:number, unitID:number, operationID:number)
	if ownerID == Game.GetLocalPlayer() then
		local pPlayer:table = Players[ownerID];
		local pUnit:table = pPlayer:GetUnits():FindID(unitID);

		if pUnit ~= nil then
			local unitInfo:table = GameInfo.Units[pUnit:GetUnitType()];
			if unitInfo.MakeTradeRoute == true then
				-- Remove entry from local players running routes
				for i, route in ipairs(m_LocalPlayerRunningRoutes) do
					if route.TraderUnitID == unitID then
						-- Add it to the last route info for trader
						if m_TradersAutomatedSettings[unitID] ~= nil and tableLength(m_TradersAutomatedSettings[unitID]) > 0 then
							m_TradersAutomatedSettings[unitID].LastRouteInfo = route;
						else
							-- Create a new entry for this trader
							print("Couldn't find trader automated info. Creating one.")
							m_TradersAutomatedSettings[unitID] = { IsAutomated=false; };
							m_TradersAutomatedSettings[unitID].LastRouteInfo = route;							
						end

						SaveTraderAutomatedInfo();

						print("Removing route " .. GetTradeRouteString(route) .. " from currently running, since it completed.");
						RemoveRouteFromTable(route, m_LocalPlayerRunningRoutes, false);
						break;
					end
				end
			end
		end
	end
end

local function TradeSupportTracker_OnPlayerTurnActivated( playerID:number, isFirstTime:boolean )
	if playerID == Game.GetLocalPlayer() and isFirstTime then
		UpdateRoutesWithTurnsRemaining(m_LocalPlayerRunningRoutes);
	end
end

-- ===========================================================================
--	Trader Route Automater - Auto renew, last route
-- ===========================================================================

function AutomateTrader(traderID:number, isAutomated:boolean, sortSettings:table)
	m_TradersAutomatedSettings[traderID] = {};
	m_TradersAutomatedSettings[traderID].IsAutomated = isAutomated;

	if sortSettings ~= nil and tableLength(sortSettings) > 0 then
		m_TradersAutomatedSettings[traderID].SortSettings = sortSettings;
	else
		m_TradersAutomatedSettings[traderID].SortSettings = nil;
	end

	--dump(m_TradersAutomatedSettings);
	SaveTraderAutomatedInfo();
end

function CancelAutomatedTrader(traderID:number)
	print("Cancelling automation for trader " .. traderID);

	LoadTraderAutomatedInfo();

	if m_TradersAutomatedSettings[traderID] ~= nil then
		m_TradersAutomatedSettings[traderID].IsAutomated = false;
		m_TradersAutomatedSettings[traderID].SortSettings = nil;

		SaveTraderAutomatedInfo();
	else
		print("Error: Could not find automated trader info");
	end
end

function RenewTradeRoutes()
	local renewedRoute:boolean = false;

	local pPlayerUnits:table = Players[Game.GetLocalPlayer()]:GetUnits();
	for i, pUnit in pPlayerUnits:Members() do
		-- Find Each Trade Unit
		local unitInfo:table = GameInfo.Units[pUnit:GetUnitType()];
		local unitID:number = pUnit:GetID();
		if unitInfo.MakeTradeRoute == true and (not pUnit:HasPendingOperations()) then
			LoadTraderAutomatedInfo();

			if m_TradersAutomatedSettings[unitID] ~= nil and m_TradersAutomatedSettings[unitID].IsAutomated then
				local destinationCity:table = nil;
				local tradeManager:table = Game.GetTradeManager();
				local originCity:table = Cities.GetCityInPlot(pUnit:GetX(), pUnit:GetY());

				if m_TradersAutomatedSettings[unitID].SortSettings ~= nil and tableLength(m_TradersAutomatedSettings[unitID].SortSettings) > 0 then
					print("Picking from top sort entry");
					local tradeRoutes:table = {};
					local players:table = Game:GetPlayers();

					-- Build list of trade routes
					for i, player in ipairs(players) do
						local cities:table = player:GetCities();
						for j, city in cities:Members() do
							-- Can we start a trade route with this city?
							if tradeManager:CanStartRoute(originCity:GetOwner(), originCity:GetID(), city:GetOwner(), city:GetID()) then
								local tradeRoute = {
									OriginCityPlayer 		= originCity:GetOwner(),
									OriginCityID 			= originCity:GetID(),
									DestinationCityPlayer 	= city:GetOwner(),
									DestinationCityID 		= city:GetID()
								};

								table.insert(tradeRoutes, tradeRoute);
							end
						end
					end

					-- Get the top route based on the settings saved when the route was begun
					local topRoute:table = GetTopRouteFromSortSettings( tradeRoutes, m_TradersAutomatedSettings[unitID].SortSettings );

					-- Get destination based on the top entry
					local destinationPlayer:table = Players[topRoute.DestinationCityPlayer];
					destinationCity = destinationPlayer:GetCities():FindID(topRoute.DestinationCityID);

				else
					print("Picking last route");
					local destinationPlayer:table = Players[m_TradersAutomatedSettings[unitID].LastRouteInfo.DestinationCityPlayer];
					destinationCity = destinationPlayer:GetCities():FindID(m_TradersAutomatedSettings[unitID].LastRouteInfo.DestinationCityID);
				end

				if destinationCity ~= nil and tradeManager:CanStartRoute(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID()) then
					local operationParams = {};
					operationParams[UnitOperationTypes.PARAM_X0] = destinationCity:GetX();
					operationParams[UnitOperationTypes.PARAM_Y0] = destinationCity:GetY();
					operationParams[UnitOperationTypes.PARAM_X1] = originCity:GetX();
					operationParams[UnitOperationTypes.PARAM_Y1] = originCity:GetY();

					if (UnitManager.CanStartOperation(pUnit, UnitOperationTypes.MAKE_TRADE_ROUTE, nil, operationParams)) then
						print("Trader " .. unitID .. " renewed its trade route to " .. Locale.Lookup(destinationCity:GetName()));
						-- TODO: Send notification for renewing routes
						UnitManager.RequestOperation(pUnit, UnitOperationTypes.MAKE_TRADE_ROUTE, operationParams);
					
						if not renewedRoute then
							renewedRoute = true;
						end
					else
						print("Could not start a route");
					end
				else
					print("Could not renew a route. Missing route info, or the destination is no longer a valid trade route destination.");
				end
			end
		end
	end

	-- Play sound, if a route was renewed.
	if renewedRoute then
		UI.PlaySound("START_TRADE_ROUTE");
	end
end

function IsTraderAutomated(traderID:number)
	LoadTraderAutomatedInfo();

	if m_TradersAutomatedSettings[traderID] ~= nil then
		return m_TradersAutomatedSettings[traderID].IsAutomated;
	end

	return false;
end

function SaveTraderAutomatedInfo()
	-- Dump active routes info
	-- print("Saving Trader Automated info in PlayerConfig database")
	local dataDump = DataDumper(m_TradersAutomatedSettings, "traderAutomatedSettings", true);
	-- print(dataDump);
	PlayerConfigurations[Game.GetLocalPlayer()]:SetValue("BTS_TraderAutomatedSettings", dataDump);
end

function LoadTraderAutomatedInfo()
	local localPlayerID = Game.GetLocalPlayer();
	if(PlayerConfigurations[localPlayerID]:GetValue("BTS_TraderAutomatedSettings") ~= nil) then
		-- print("Retrieving trader automated settings from PlayerConfig database")
		local dataDump = PlayerConfigurations[localPlayerID]:GetValue("BTS_TraderAutomatedSettings");
		-- print(dataDump);
		loadstring(dataDump)();
		m_TradersAutomatedSettings = traderAutomatedSettings;
	else
		print("No running route data was found, on load.")
	end
end

-- ---------------------------------------------------------------------------
-- Game event hookups (Local to this file)
-- ---------------------------------------------------------------------------

local function TradeSupportAutomater_OnPlayerTurnActivated( playerID:number, isFirstTime:boolean )
	if playerID == Game.GetLocalPlayer() and isFirstTime then
		RenewTradeRoutes();
	end
end

-- ===========================================================================
--	Trade Route Sorter
-- ===========================================================================

-- This requires sort settings table passed.
function SortTradeRoutes( tradeRoutes:table, sortSettings:table )
	if tableLength(sortSettings) > 0 then
		table.sort(tradeRoutes, function(a, b) return CompleteCompareBy(a, b, sortSettings); end );
	end
end

function GetTopRouteFromSortSettings( tradeRoutes:table, sortSettings:table )
	if tableLength(sortSettings) > 0 then
		return GetMinEntry(tradeRoutes, function(a, b) return CompleteCompareBy(a, b, sortSettings); end );
	end

	-- if no sort settings, return top entry
	return tradeRoutes[1];
end

-- ---------------------------------------------------------------------------
-- Sort Entries functions
-- ---------------------------------------------------------------------------

function InsertSortEntry( sortByID:number, sortOrder:number, sortSettings:table )
	local sortEntry = {
		SortByID = sortByID,
		SortOrder = sortOrder
	};

	-- Only insert if it does not exist
	local sortEntryIndex = findIndex (sortSettings, sortEntry, CompareSortEntries);
	if sortEntryIndex == -1 then
		-- print("Inserting " .. sortEntry.SortByID);
		table.insert(sortSettings, sortEntry);
	else
		-- If it exists, just update the sort oder
		-- print("Index: " .. sortEntryIndex);
		sortSettings[sortEntryIndex].SortOrder = sortOrder;
	end
end

function RemoveSortEntry( sortByID:number, sortSettings:table  )
	local sortEntry = {
		SortByID = sortByID,
		SortOrder = sortOrder
	};

	-- Only delete if it exists
	local sortEntryIndex:number = findIndex(sortSettings, sortEntry, CompareSortEntries);

	if (sortEntryIndex > 0) then
		table.remove(sortSettings, sortEntryIndex);
	end
end

-- Checks for the same ID, not the same order
function CompareSortEntries( sortEntry1:table, sortEntry2:table)
	if sortEntry1.SortByID == sortEntry2.SortByID then
		return true;
	end

	return false;
end

-- ---------------------------------------------------------------------------
-- Yield/Turn Compare functions
-- ---------------------------------------------------------------------------

function CompareByFood( tradeRoute1:table, tradeRoute2:table )
	return CompareByYield (GameInfo.Yields["YIELD_FOOD"].Index, tradeRoute1, tradeRoute2);
end

function CompareByProduction( tradeRoute1:table, tradeRoute2:table )
	return CompareByYield (GameInfo.Yields["YIELD_PRODUCTION"].Index, tradeRoute1, tradeRoute2);
end

function CompareByGold( tradeRoute1:table, tradeRoute2:table )
	return CompareByYield (GameInfo.Yields["YIELD_GOLD"].Index, tradeRoute1, tradeRoute2);
end

function CompareByScience( tradeRoute1:table, tradeRoute2:table )
	return CompareByYield (GameInfo.Yields["YIELD_SCIENCE"].Index, tradeRoute1, tradeRoute2);
end

function CompareByCulture( tradeRoute1:table, tradeRoute2:table )
	return CompareByYield (GameInfo.Yields["YIELD_CULTURE"].Index, tradeRoute1, tradeRoute2);
end

function CompareByFaith( tradeRoute1:table, tradeRoute2:table )
	return CompareByYield (GameInfo.Yields["YIELD_FAITH"].Index, tradeRoute1, tradeRoute2);
end

function CompareByYield( yieldIndex:number, tradeRoute1:table, tradeRoute2:table )
	local originPlayer1:table = Players[tradeRoute1.OriginCityPlayer];
	local destinationPlayer1:table = Players[tradeRoute1.DestinationCityPlayer];
	local originCity1:table = originPlayer1:GetCities():FindID(tradeRoute1.OriginCityID);
	local destinationCity1:table = destinationPlayer1:GetCities():FindID(tradeRoute1.DestinationCityID);

	local originPlayer2:table = Players[tradeRoute2.OriginCityPlayer];
	local destinationPlayer2:table = Players[tradeRoute2.DestinationCityPlayer];
	local originCity2:table = originPlayer2:GetCities():FindID(tradeRoute2.OriginCityID);
	local destinationCity2:table = destinationPlayer2:GetCities():FindID(tradeRoute2.DestinationCityID);

	local yieldForRoute1 = GetYieldForOriginCity(yieldIndex, originCity1, destinationCity1);
	local yieldForRoute2 = GetYieldForOriginCity(yieldIndex, originCity2, destinationCity2);

	return yieldForRoute1 < yieldForRoute2;
end

function CompareByTurnsToComplete( tradeRoute1:table, tradeRoute2:table )
	-- If the route has turns remaining entry, compare them
	if tradeRoute1.TurnsRemaining ~= nil and tradeRoute2.TurnsRemaining ~= nil then
		return tradeRoute1.TurnsRemaining < tradeRoute2.TurnsRemaining;
	end

	local originPlayer1:table = Players[tradeRoute1.OriginCityPlayer];
	local destinationPlayer1:table = Players[tradeRoute1.DestinationCityPlayer];
	local originCity1:table = originPlayer1:GetCities():FindID(tradeRoute1.OriginCityID);
	local destinationCity1:table = destinationPlayer1:GetCities():FindID(tradeRoute1.DestinationCityID);

	local originPlayer2:table = Players[tradeRoute2.OriginCityPlayer];
	local destinationPlayer2:table = Players[tradeRoute2.DestinationCityPlayer];
	local originCity2:table = originPlayer2:GetCities():FindID(tradeRoute2.OriginCityID);
	local destinationCity2:table = destinationPlayer2:GetCities():FindID(tradeRoute2.DestinationCityID);

	local tradePathLength1, tripsToDestination1, turnsToCompleteRoute1 = GetRouteInfo(originCity1, destinationCity1);
	local tradePathLength2, tripsToDestination2, turnsToCompleteRoute2 = GetRouteInfo(originCity2, destinationCity2);

	return turnsToCompleteRoute1 < turnsToCompleteRoute2;
end

function CompareByNetYield( tradeRoute1:table, tradeRoute2:table )
	local originPlayer1:table = Players[tradeRoute1.OriginCityPlayer];
	local destinationPlayer1:table = Players[tradeRoute1.DestinationCityPlayer];
	local originCity1:table = originPlayer1:GetCities():FindID(tradeRoute1.OriginCityID);
	local destinationCity1:table = destinationPlayer1:GetCities():FindID(tradeRoute1.DestinationCityID);

	local originPlayer2:table = Players[tradeRoute2.OriginCityPlayer];
	local destinationPlayer2:table = Players[tradeRoute2.DestinationCityPlayer];
	local originCity2:table = originPlayer2:GetCities():FindID(tradeRoute2.OriginCityID);
	local destinationCity2:table = destinationPlayer2:GetCities():FindID(tradeRoute2.DestinationCityID);

	local yieldForRoute1:number = 0;
	local yieldForRoute2:number = 0;

	for yieldInfo in GameInfo.Yields() do
		yieldForRoute1 = yieldForRoute1 + GetYieldForOriginCity(yieldInfo.Index, originCity1, destinationCity1);
		yieldForRoute2 = yieldForRoute2 + GetYieldForOriginCity(yieldInfo.Index, originCity2, destinationCity2);
	end

	return yieldForRoute1 < yieldForRoute2;
end

-- Uses the list of compare functions in sort settings, to make one total compare function
-- Used to sort trade routes
function CompleteCompareBy( tradeRoute1:table, tradeRoute2:table, sortSettings:table )
	if tradeRoute1 == nil or tradeRoute2 == nil or sortSettings == nil then
		-- print("Error: Passed table was nil.");
		return false;
	end

	for index, sortEntry in ipairs(sortSettings) do
		local compareFunction = CompareFunctionByID[sortEntry.SortByID];
		local compareResult:boolean = compareFunction(tradeRoute1, tradeRoute2);

		if compareResult then
			if (sortEntry.SortOrder == SORT_DESCENDING) then
				return false;
			else
				return true;
			end
		elseif not CheckEqualityWithCompare( tradeRoute1, tradeRoute2, compareFunction ) then
			if (sortEntry.SortOrder == SORT_DESCENDING) then
				return true;
			else
				return false;
			end
		end
	end

	-- If it reaches here, we used all the settings, and all of them were equal. 
	-- Do net yield compare. because order should be in descending
	if CompareByNetYield(tradeRoute1, tradeRoute2) then
		return false;
	end

	return true;
end

-- ===========================================================================
--	General Helper functions
-- ===========================================================================

-- Simple check to seeif player1 and player2 can possibly have a trade route.
function CanPossiblyTradeWithPlayer(player1, player2)
	if player1 == player2 then return true; end

	local pPlayer1 = Players[player1];
	local pPlayer1Diplomacy = pPlayer1:GetDiplomacy();
	local pPlayer2 = Players[player2]

	if pPlayer2:IsAlive() and pPlayer1Diplomacy:HasMet(player2) then
		if not pPlayer1Diplomacy:IsAtWarWith(player2) then
			return true;
		end
	end

	return false;
end

function IsRoutePossible(originCityPlayerID, originCityID, destinationCityPlayerID, destinationCityID)
	local tradeManager:table = Game.GetTradeManager();

	return tradeManager:CanStartRoute(originCityPlayerID, originCityID, destinationCityPlayerID, destinationCityID);
end

function FormatYieldText(yieldInfo, yieldAmount)
	local text:string = "";

	local iconString = "";
	if (yieldInfo.YieldType == "YIELD_FOOD") then
		iconString = "[ICON_Food]";
	elseif (yieldInfo.YieldType == "YIELD_PRODUCTION") then
		iconString = "[ICON_Production]";
	elseif (yieldInfo.YieldType == "YIELD_GOLD") then
		iconString = "[ICON_Gold]";
	elseif (yieldInfo.YieldType == "YIELD_SCIENCE") then
		iconString = "[ICON_Science]";
	elseif (yieldInfo.YieldType == "YIELD_CULTURE") then
		iconString = "[ICON_Culture]";
	elseif (yieldInfo.YieldType == "YIELD_FAITH") then
		iconString = "[ICON_Faith]";
	end

	if (yieldAmount >= 0) then
		text = text .. "+";
	end

	text = text .. yieldAmount;
	return iconString, text;
end

-- Finds and removes routeToDelete from routeTable
function RemoveRouteFromTable( routeToDelete:table , routeTable:table, groupedRoutes:boolean )
	-- If grouping by something, go one level deeper
	if groupedRoutes then
		local targetIndex:number;
		local targetGroupIndex:number;

		for i, groupedRoutes in ipairs(routeTable) do
			for j, route in ipairs(groupedRoutes) do
				if CheckRouteEquality( route, routeToDelete ) then
					targetIndex = j;
					targetGroupIndex = i;
				end
			end
		end

		-- Remove route
		if targetIndex then
			table.remove(routeTable[targetGroupIndex], targetIndex);
		end
		-- If that group is empty, remove that group
		if tableLength(routeTable[targetGroupIndex]) <= 0 then
			if targetGroupIndex then
				table.remove(routeTable, targetGroupIndex);
			end
		end
	else
		local targetIndex:number;

		for i, route in ipairs(routeTable) do
			if CheckRouteEquality( route, routeToDelete ) then
				targetIndex = i;
			end		
		end

		-- Remove route
		if targetIndex then
			table.remove(routeTable, targetIndex);
		end
	end
end

-- Get idle Trade Units by Player ID
function GetIdleTradeUnits( playerID:number )
	local idleTradeUnits:table = {};

	-- Loop through the Players units
	local localPlayerUnits:table = Players[playerID]:GetUnits();
	for i,unit in localPlayerUnits:Members() do

		-- Find any trade units
		local unitInfo:table = GameInfo.Units[unit:GetUnitType()];
		if unitInfo.MakeTradeRoute then
			local doestradeUnitHasRoute:boolean = false;

			-- Determine if those trade units are busy by checking outgoing routes from the players cities
			local localPlayerCities:table = Players[playerID]:GetCities();
			for i,city in localPlayerCities:Members() do
				local routes = city:GetTrade():GetOutgoingRoutes();
				for i,route in ipairs(routes) do
					if route.TraderUnitID == unit:GetID() then
						doestradeUnitHasRoute = true;
					end
				end
			end

			-- If this trade unit isn't attached to an outgoing route then they are idle
			if not doestradeUnitHasRoute then
				table.insert(idleTradeUnits, unit);
			end
		end
	end

	return idleTradeUnits;
end

-- Returns a string of the route in format "[ORIGIN_CITY_NAME]-[DESTINATION_CITY_NAME]"
function GetTradeRouteString( routeInfo:table )
	local originPlayer:table = Players[routeInfo.OriginCityPlayer];
	local originCity:table = originPlayer:GetCities():FindID(routeInfo.OriginCityID);

	local destinationPlayer:table = Players[routeInfo.DestinationCityPlayer];
	local destinationCity:table = destinationPlayer:GetCities():FindID(routeInfo.DestinationCityID);

	local originCityName:string = "[NOT_FOUND]";
	if originCity ~= nil then
		originCityName = Locale.Lookup(originCity:GetName());
	end

	local destinationCityName:string = "[NOT_FOUND]";
	if destinationCity ~= nil then
		destinationCityName = Locale.Lookup(destinationCity:GetName());
	end
	
	return originCityName .. "-" .. destinationCityName;
end

function GetTradeRouteYieldString( routeInfo )
	local returnString:string = "";
	local originPlayer:table = Players[routeInfo.OriginCityPlayer];
	local originCity:table = originPlayer:GetCities():FindID(routeInfo.OriginCityID);

	local destinationPlayer:table = Players[routeInfo.DestinationCityPlayer];
	local destinationCity:table = destinationPlayer:GetCities():FindID(routeInfo.DestinationCityID);


	for yieldInfo in GameInfo.Yields() do
		local originCityYieldValue = GetYieldForOriginCity(yieldInfo.Index, originCity, destinationCity);
		
		local iconString, text = FormatYieldText(yieldInfo, originCityYieldValue);
		
		if originCityYieldValue == 0 then
			iconString = "";
			text = "";
		end

		if (yieldInfo.YieldType == "YIELD_FOOD") then
			returnString = returnString .. text .. iconString .. " ";
		elseif (yieldInfo.YieldType == "YIELD_PRODUCTION") then
			returnString = returnString .. text .. iconString .. " ";
		elseif (yieldInfo.YieldType == "YIELD_GOLD") then
			returnString = returnString .. text .. iconString .. " ";
		elseif (yieldInfo.YieldType == "YIELD_SCIENCE") then
			returnString = returnString .. text .. iconString .. " ";
		elseif (yieldInfo.YieldType == "YIELD_CULTURE") then
			returnString = returnString .. text .. iconString .. " ";
		elseif (yieldInfo.YieldType == "YIELD_FAITH") then
			returnString = returnString .. text .. iconString;
		end
	end

	return returnString;
end

-- Checks if the two routes are the same (does not compare traderUnit)
function CheckRouteEquality ( tradeRoute1:table, tradeRoute2:table )
	if ( 	tradeRoute1.OriginCityPlayer == tradeRoute2.OriginCityPlayer and
			tradeRoute1.OriginCityID == tradeRoute2.OriginCityID and
			tradeRoute1.DestinationCityPlayer == tradeRoute2.DestinationCityPlayer and
			tradeRoute1.DestinationCityID == tradeRoute2.DestinationCityID ) then
		return true;
	end

	return false;
end

-- Checks equality with the passed sorting compare function
function CheckEqualityWithCompare( tradeRoute1:table, tradeRoute2:table, compareFunction )
	if not compareFunction(tradeRoute1, tradeRoute2) then
		if not compareFunction(tradeRoute2, tradeRoute1) then
			return true;
		end
	end

	return false;
end

-- Returns yield for the origin city
function GetYieldForOriginCity( yieldIndex:number, originCity:table, destinationCity:table )
	local tradeManager = Game.GetTradeManager();

	-- From route
	local yieldValue = tradeManager:CalculateOriginYieldFromPotentialRoute(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID(), yieldIndex);
	-- From path
	yieldValue = yieldValue + tradeManager:CalculateOriginYieldFromPath(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID(), yieldIndex);
	-- From modifiers
	local resourceID = -1;
	yieldValue = yieldValue + tradeManager:CalculateOriginYieldFromModifiers(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID(), yieldIndex, resourceID);

	return yieldValue;
end

-- Returns yield for the destination city
function GetYieldForDestinationCity( yieldIndex:number, originCity:table, destinationCity:table )
	local tradeManager = Game.GetTradeManager();

	-- From route
	local yieldValue = tradeManager:CalculateDestinationYieldFromPotentialRoute(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID(), yieldIndex);
	-- From path
	yieldValue = yieldValue + tradeManager:CalculateDestinationYieldFromPath(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID(), yieldIndex);
	-- From modifiers
	local resourceID = -1;
	yieldValue = yieldValue + tradeManager:CalculateDestinationYieldFromModifiers(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID(), yieldIndex, resourceID);

	return yieldValue;
end

-- Returns length of trade path, number of trips to destination, turns to complete route
function GetRouteInfo(originCity:table, destinationCity:table)
	local eSpeed = GameConfiguration.GetGameSpeedType();
	
	if GameInfo.GameSpeeds[eSpeed] ~= nil then
		local iSpeedCostMultiplier = GameInfo.GameSpeeds[eSpeed].CostMultiplier;
		local tradeManager = Game.GetTradeManager();
		local pathPlots = tradeManager:GetTradeRoutePath(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID() );
		local tradePathLength:number = tableLength(pathPlots) - 1;
		local multiplierConstant:number = 0.1;

		local tripsToDestination = 1 + math.floor(iSpeedCostMultiplier/tradePathLength * multiplierConstant);
		
		--print("Error: Playing on an unrecognized speed. Defaulting to standard for route turns calculation");
		local turnsToCompleteRoute = (tradePathLength * 2 * tripsToDestination);
		return tradePathLength, tripsToDestination, turnsToCompleteRoute;
	else
		print("Speed type index " .. eSpeed);
		print("Error: Could not find game speed type. Defaulting to first entry in table");
		local iSpeedCostMultiplier =  GameInfo.GameSpeeds[1].CostMultiplier;
		local tradeManager = Game.GetTradeManager();
		local pathPlots = tradeManager:GetTradeRoutePath(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID() );
		local tradePathLength:number = tableLength(pathPlots) - 1;
		local multiplierConstant:number = 0.1;

		local tripsToDestination = 1 + math.floor(iSpeedCostMultiplier/tradePathLength * multiplierConstant);
		local turnsToCompleteRoute = (tradePathLength * 2 * tripsToDestination);
		return tradePathLength, tripsToDestination, turnsToCompleteRoute;
	end
end

-- ===========================================================================
--	Helper Utility functions
-- ===========================================================================

function tableLength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

function reverseTable(T)
	table_length = tableLength(T);

	for i=1, math.floor(table_length / 2) do
		local tmp = T[i]
		T[i] = T[table_length - i + 1]
		T[table_length - i + 1] = tmp
	end
end

function findIndex(T, searchItem, compareFunc)
	for index, item in ipairs(T) do
		if compareFunc(item, searchItem) then
			return index;
		end
	end

	return -1;
end

function GetMinEntry(searchTable, compareFunc)
	local minEntry = searchTable[1];
	for index, entry in ipairs(searchTable) do
		if not compareFunc(minEntry, entry) then
			minEntry = entry;
		end
	end
	return minEntry;
end

-- ========== START OF DataDumper.lua =================
--[[ License DataDumper.lua
	Copyright (c) 2007 Olivetti-Engineering SA

	Permission is hereby granted, free of charge, to any person
	obtaining a copy of this software and associated documentation
	files (the "Software"), to deal in the Software without
	restriction, including without limitation the rights to use,
	copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the
	Software is furnished to do so, subject to the following
	conditions:

	The above copyright notice and this permission notice shall be
	included in all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
	OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
	HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
	WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
	OTHER DEALINGS IN THE SOFTWARE.
]]

function dump(...)
  print(DataDumper(...), "\n---")
end

local dumplua_closure = [[
	local closures = {}
	local function closure(t)
	  closures[#closures+1] = t
	  t[1] = assert(loadstring(t[1]))
	  return t[1]
	end

	for _,t in pairs(closures) do
	  for i = 2,#t do
		debug.setupvalue(t[1], i-1, t[i])
	  end
	end
]]

local lua_reserved_keywords = {
  'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
  'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat',
  'return', 'then', 'true', 'until', 'while' 
}

local function keys(t)
  local res = {}
  local oktypes = { stringstring = true, numbernumber = true }
  local function cmpfct(a,b)
	if oktypes[type(a)..type(b)] then
	  return a < b
	else
	  return type(a) < type(b)
	end
  end
  for k in pairs(t) do
	res[#res+1] = k
  end
  table.sort(res, cmpfct)
  return res
end

local c_functions = {}
for _,lib in pairs{'_G', 'string', 'table', 'math',
	'io', 'os', 'coroutine', 'package', 'debug'} do
  local t = {}
  lib = lib .. "."
  if lib == "_G." then lib = "" end
  for k,v in pairs(t) do
	if type(v) == 'function' and not pcall(string.dump, v) then
	  c_functions[v] = lib..k
	end
  end
end

function DataDumper(value, varname, fastmode, ident)
  local defined, dumplua = {}
  -- Local variables for speed optimization
  local string_format, type, string_dump, string_rep =
		string.format, type, string.dump, string.rep
  local tostring, pairs, table_concat =
		tostring, pairs, table.concat
  local keycache, strvalcache, out, closure_cnt = {}, {}, {}, 0
  setmetatable(strvalcache, {__index = function(t,value)
	local res = string_format('%q', value)
	t[value] = res
	return res
  end})
  local fcts = {
	string = function(value) return strvalcache[value] end,
	number = function(value) return value end,
	boolean = function(value) return tostring(value) end,
	['nil'] = function(value) return 'nil' end,
	['function'] = function(value)
	  return string_format("loadstring(%q)", string_dump(value))
	end,
	userdata = function() error("Cannot dump userdata") end,
	thread = function() error("Cannot dump threads") end,
  }
  local function test_defined(value, path)
	if defined[value] then
	  if path:match("^getmetatable.*%)$") then
		out[#out+1] = string_format("s%s, %s)\n", path:sub(2,-2), defined[value])
	  else
		out[#out+1] = path .. " = " .. defined[value] .. "\n"
	  end
	  return true
	end
	defined[value] = path
  end
  local function make_key(t, key)
	local s
	if type(key) == 'string' and key:match('^[_%a][_%w]*$') then
	  s = key .. "="
	else
	  s = "[" .. dumplua(key, 0) .. "]="
	end
	t[key] = s
	return s
  end
  for _,k in ipairs(lua_reserved_keywords) do
	keycache[k] = '["'..k..'"] = '
  end
  if fastmode then
	fcts.table = function (value)
	  -- Table value
	  local numidx = 1
	  out[#out+1] = "{"
	  for key,val in pairs(value) do
		if key == numidx then
		  numidx = numidx + 1
		else
		  out[#out+1] = keycache[key]
		end
		local str = dumplua(val)
		out[#out+1] = str..","
	  end
	  if string.sub(out[#out], -1) == "," then
		out[#out] = string.sub(out[#out], 1, -2);
	  end
	  out[#out+1] = "}"
	  return ""
	end
  else
	fcts.table = function (value, ident, path)
	  if test_defined(value, path) then return "nil" end
	  -- Table value
	  local sep, str, numidx, totallen = " ", {}, 1, 0
	  local meta, metastr = getmetatable(value)
	  if meta then
		ident = ident + 1
		metastr = dumplua(meta, ident, "getmetatable("..path..")")
		totallen = totallen + #metastr + 16
	  end
	  for _,key in pairs(keys(value)) do
		local val = value[key]
		local s = ""
		local subpath = path or ""
		if key == numidx then
		  subpath = subpath .. "[" .. numidx .. "]"
		  numidx = numidx + 1
		else
		  s = keycache[key]
		  if not s:match "^%[" then subpath = subpath .. "." end
		  subpath = subpath .. s:gsub("%s*=%s*$","")
		end
		s = s .. dumplua(val, ident+1, subpath)
		str[#str+1] = s
		totallen = totallen + #s + 2
	  end
	  if totallen > 80 then
		sep = "\n" .. string_rep("  ", ident+1)
	  end
	  str = "{"..sep..table_concat(str, ","..sep).." "..sep:sub(1,-3).."}"
	  if meta then
		sep = sep:sub(1,-3)
		return "setmetatable("..sep..str..","..sep..metastr..sep:sub(1,-3)..")"
	  end
	  return str
	end
	fcts['function'] = function (value, ident, path)
	  if test_defined(value, path) then return "nil" end
	  if c_functions[value] then
		return c_functions[value]
	  elseif debug == nil or debug.getupvalue(value, 1) == nil then
		return string_format("loadstring(%q)", string_dump(value))
	  end
	  closure_cnt = closure_cnt + 1
	  local res = {string.dump(value)}
	  for i = 1,math.huge do
		local name, v = debug.getupvalue(value,i)
		if name == nil then break end
		res[i+1] = v
	  end
	  return "closure " .. dumplua(res, ident, "closures["..closure_cnt.."]")
	end
  end
  function dumplua(value, ident, path)
	return fcts[type(value)](value, ident, path)
  end
  if varname == nil then
	varname = ""
  elseif varname:match("^[%a_][%w_]*$") then
	varname = varname .. " = "
  end
  if fastmode then
	setmetatable(keycache, {__index = make_key })
	out[1] = varname
	table.insert(out,dumplua(value, 0))
	return table.concat(out)
  else
	setmetatable(keycache, {__index = make_key })
	local items = {}
	for i=1,10 do items[i] = '' end
	items[3] = dumplua(value, ident or 0, "t")
	if closure_cnt > 0 then
	  items[1], items[6] = dumplua_closure:match("(.*\n)\n(.*)")
	  out[#out+1] = ""
	end
	if #out > 0 then
	  items[2], items[4] = "local t = ", "\n"
	  items[5] = table.concat(out)
	  items[7] = varname .. "t"
	else
	  items[2] = varname
	end
	return table.concat(items)
  end
end

-- ========== END OF DataDumper.lua =================

-- ===========================================================================
--	Event handlers
-- ===========================================================================

function TradeSupportTracker_Initialize()
	print("Initializing BTS Trade Support Tracker");

	-- Load Previous Routes
	LoadRunningRoutesInfo();

	Events.UnitOperationStarted.Add( TradeSupportTracker_OnUnitOperationStarted );
	Events.UnitOperationsCleared.Add( TradeSupportTracker_OnUnitOperationsCleared );
	Events.PlayerTurnActivated.Add( TradeSupportTracker_OnPlayerTurnActivated );
end

function TradeSupportAutomater_Initialize()
	print("Initializing BTS Trade Support Automater");

	Events.PlayerTurnActivated.Add( TradeSupportAutomater_OnPlayerTurnActivated );
end