
local PANEL = {}

AccessorFunc(PANEL, "active", "Active", FORCE_BOOL)

local COLOR_FADED = Color(200, 200, 200, 100)
local COLOR_ACTIVE = color_white

function PANEL:Init()
	local border = 32
	local scrW, scrH = ScrW(), ScrH()
	local w, h = scrW * 0.4, scrH * 0.375

	ix.gui.chat = self

	self:SetSize(w, h)
	self:SetPos(border, scrH - h - border)

	self.active = false

	self.tabs = self:Add("DPanel")
	self.tabs:Dock(TOP)
	self.tabs:SetTall(24)
	self.tabs:DockPadding(3, 3, 3, 3)
	self.tabs:DockMargin(4, 4, 4, 4)
	self.tabs:SetVisible(false)

	self.autocompleteIndex = 0
	self.potentialCommands = {}
	self.arguments = {}

	self.scroll = self:Add("DScrollPanel")
	self.scroll:SetPos(4, 30)
	self.scroll:SetSize(w - 8, h - 70)
	self.scroll:GetVBar():SetWide(0)
	self.scroll.PaintOver = function(panel, panelWidth, panelHeight)
		local entry = self.text

		if (self.active and IsValid(entry)) then
			local text = entry:GetText()

			if (text:sub(1, 1) == "/") then
				local arguments = self.arguments or {}
				local command = string.PatternSafe(arguments[1] or ""):lower()

				ix.util.DrawBlur(panel)

				surface.SetDrawColor(0, 0, 0, 200)
				surface.DrawRect(0, 0, panelWidth, panelHeight)

				local currentY = 0

				for k, v in ipairs(self.potentialCommands) do
					local color = ix.config.Get("color")
					local bSelectedCommand = (self.autocompleteIndex == 0 and command == v.uniqueID) or
						(self.autocompleteIndex > 0 and k == self.autocompleteIndex)

					if (bSelectedCommand) then
						local description = v:GetDescription()

						if (description != "") then
							local _, height = ix.util.DrawText(description, 4, currentY, COLOR_ACTIVE)

							currentY = currentY + height + 1
						end

						color = Color(color.r + 35, color.g + 35, color.b + 35, 255)
					end

					local x, height = ix.util.DrawText("/" .. v.name .. "  ", 4, currentY, color)

					if (bSelectedCommand and v.syntax) then
						local i2 = 0

						for argument in v.syntax:gmatch("([%[<][%w_]+[%s][%w_]+[%]>])") do
							i2 = i2 + 1
							color = COLOR_FADED

							if (i2 == (#arguments - 1)) then
								color = COLOR_ACTIVE
							end

							local width, _ = ix.util.DrawText(argument .. "  ", x, currentY, color)

							x = x + width
						end
					end

					currentY = currentY + height + 1
				end
			end
		end
	end

	self.lastY = 0

	self.list = {}
	self.filtered = {}

	-- luacheck: globals chat
	chat.GetChatBoxPos = function()
		return self:LocalToScreen(0, 0)
	end

	chat.GetChatBoxSize = function()
		return self:GetSize()
	end

	local buttons = {}

	for _, v in SortedPairsByMemberValue(ix.chat.classes, "filter") do
		if (!buttons[v.filter]) then
			self:AddFilterButton(v.filter)
			buttons[v.filter] = true
		end
	end
end

function PANEL:Paint(w, h)
	if (self.active) then
		ix.util.DrawBlur(self, 10)

		surface.SetDrawColor(250, 250, 250, 2)
		surface.DrawRect(0, 0, w, h)

		surface.SetDrawColor(0, 0, 0, 240)
		surface.DrawOutlinedRect(0, 0, w, h)
	end
end

local TEXT_COLOR = Color(255, 255, 255, 200)

function PANEL:SetActive(state)
	self.active = tobool(state)

	if (state) then
		-- we don't need to create if the panel already exists
		if (IsValid(self.entry)) then
			return
		end

		self.entry = self:Add("EditablePanel")
		self.entry:SetPos(self.x + 4, self.y + self:GetTall() - 32)
		self.entry:SetWide(self:GetWide() - 8)
		self.entry.Paint = function(this, w, h)
		end
		self.entry.OnRemove = function()
			hook.Run("FinishChat")
		end
		self.entry:SetTall(28)

		ix.chat.history = ix.chat.history or {}

		self.text = self.entry:Add("DTextEntry")
		self.text.baseClass = baseclass.Get("DTextEntry")
		self.text:Dock(FILL)
		self.text.History = ix.chat.history
		self.text:SetHistoryEnabled(true)
		self.text:DockMargin(3, 3, 3, 3)
		self.text:SetFont("ixChatFont")
		self.text.OnEnter = function(this)
			local text = this:GetText()

			this:Remove()

			self.tabs:SetVisible(false)
			self.active = false
			self.entry:Remove()

			if (text:find("%S")) then
				if (!(ix.chat.lastLine or ""):find(text, 1, true)) then
					ix.chat.history[#ix.chat.history + 1] = text
					ix.chat.lastLine = text
				end

				netstream.Start("msg", text)
			end
		end
		self.text:SetAllowNonAsciiCharacters(true)
		self.text.Paint = function(this, w, h)
			surface.SetDrawColor(0, 0, 0, 100)
			surface.DrawRect(0, 0, w, h)

			surface.SetDrawColor(0, 0, 0, 200)
			surface.DrawOutlinedRect(0, 0, w, h)

			this:DrawTextEntryText(TEXT_COLOR, ix.config.Get("color"), TEXT_COLOR)
		end
		self.text.AllowInput = function(this, newText)
			local text = this:GetText()
			local maxLength = ix.config.Get("chatMax")

			if (string.len(text..newText) > maxLength) then
				surface.PlaySound("common/talk.wav")
				return true
			end
		end
		self.text.Think = function(this)
			local text = this:GetText()
			local maxLength = ix.config.Get("chatMax")

			if (string.len(text) > maxLength) then
				local newText = string.sub(text, 0, maxLength)

				this:SetText(newText)
				this:SetCaretPos(string.len(newText))
			end
		end
		self.text.OnTextChanged = function(this)
			local text = this:GetText()

			hook.Run("ChatTextChanged", text)

			if (text:sub(1, 1) == "/" and !this.autocompleted) then
				local command = tostring(text:match("(/(%w+))") or "/")

				self.potentialCommands = ix.command.FindAll(command, true, true, true)
				self.arguments = ix.command.ExtractArgs(text:sub(2))

				-- if the first suggested command is equal to the currently typed one,
				-- offset the index so you don't have to hit tab twice to go past the first command
				if (#self.potentialCommands > 0 and self.potentialCommands[1].uniqueID == command:sub(2):lower()) then
					self.autocompleteIndex = 1
				else
					self.autocompleteIndex = 0
				end
			end

			this.autocompleted = nil
		end
		self.text.OnKeyCodeTyped = function(this, code)
			if (code == KEY_TAB) then
				if (#self.potentialCommands > 0) then
					self.autocompleteIndex = (self.autocompleteIndex + 1) > #self.potentialCommands and 1 or (self.autocompleteIndex + 1)

					local command = self.potentialCommands[self.autocompleteIndex]

					if (command) then
						local text = string.format("/%s ", command.uniqueID)

						this:SetText(text)
						this:SetCaretPos(text:len())

						this.autocompleted = true
					end
				end

				this:RequestFocus()
				return true
			else
				this.baseClass.OnKeyCodeTyped(this, code)
			end
		end

		self.entry:MakePopup()
		self.text:RequestFocus()
		self.tabs:SetVisible(true)

		hook.Run("StartChat")
	elseif (IsValid(self.entry)) then
		self.entry:Remove()
	end
end

local function OnDrawText(text, font, x, y, color, alignX, alignY, alpha)
	alpha = alpha or 255

	surface.SetTextPos(x+1, y+1)
	surface.SetTextColor(0, 0, 0, alpha)
	surface.SetFont(font)
	surface.DrawText(text)

	surface.SetTextPos(x, y)
	surface.SetTextColor(color.r, color.g, color.b, alpha)
	surface.SetFont(font)
	surface.DrawText(text)
	--draw.SimpleTextOutlined(text, font, x, y, ColorAlpha(color, alpha), 0, alignY, 1, ColorAlpha(color_black, alpha * 0.6))
end

local function PaintFilterButton(this, w, h)
	if (this.active) then
		surface.SetDrawColor(40, 40, 40)
	else
		local alpha = 120 + math.cos(RealTime() * 5) * 10

		surface.SetDrawColor(ColorAlpha(ix.config.Get("color"), alpha))
	end

	surface.DrawRect(0, 0, w, h)

	surface.SetDrawColor(0, 0, 0, 200)
	surface.DrawOutlinedRect(0, 0, w, h)
end

function PANEL:AddFilterButton(filter)
	local name = L(filter)

	local tab = self.tabs:Add("DButton")
	tab:SetFont("ixChatFont")
	tab:SetText(name:upper())
	tab:SizeToContents()
	tab:DockMargin(0, 0, 3, 0)
	tab:SetWide(tab:GetWide() + 32)
	tab:Dock(LEFT)
	tab:SetTextColor(color_white)
	tab:SetExpensiveShadow(1, Color(0, 0, 0, 200))
	tab.Paint = PaintFilterButton
	tab.DoClick = function(this)
		this.active = !this.active

		local filters = ix.option.Get("chatFilter", ""):lower()

		if (filters == "none") then
			filters = ""
		end

		if (this.active) then
			filters = filters..filter..","
		else
			filters = filters:gsub(filter.."[,]", "")

			if (!filters:find("%S")) then
				filters = "none"
			end
		end

		self:SetFilter(filter, this.active)
		ix.option.Set("chatFilter", filters)
	end

	if (ix.option.Get("chatFilter", ""):lower():find(filter)) then
		tab.active = true
	end
end

function PANEL:AddText(...)
	local text = "<font=ixChatFont>"

	if (ix.option.Get("chatTimestamps", false)) then
		text = text .. "<color=150,150,150>("

		if (ix.option.Get("24hourTime", false)) then
			text = text .. os.date("%H:%M")
		else
			text = text .. os.date("%I:%M %p")
		end

		text = text .. ") "
	end

	if (CHAT_CLASS) then
		text = text .. "<font="..(CHAT_CLASS.font or "ixChatFont")..">"
	end

	for _, v in ipairs({...}) do
		if (type(v) == "IMaterial") then
			local texture = v:GetName()

			if (texture) then
				text = text.."<img="..texture..","..v:Width().."x"..v:Height().."> "
			end
		elseif (type(v) == "table" and v.r and v.g and v.b) then
			text = text.."<color="..v.r..","..v.g..","..v.b..">"
		elseif (type(v) == "Player") then
			local color = team.GetColor(v:Team())

			text = text.."<color="..color.r..","..color.g..","..color.b..">"..v:Name():gsub("<", "&lt;"):gsub(">", "&gt;")
		else
			text = text..tostring(v):gsub("<", "&lt;"):gsub(">", "&gt;")
			text = text:gsub("%b**", function(value)
				local inner = value:sub(2, -2)

				if (inner:find("%S")) then
					return "<font=ixChatFontItalics>"..value:sub(2, -2).."</font>"
				end
			end)
		end
	end

	text = text.."</font>"

	local panel = self.scroll:Add("ixMarkupPanel")
	panel:SetWide(self:GetWide() - 8)
	panel:SetMarkup(text, OnDrawText)
	panel.start = CurTime() + 15
	panel.finish = panel.start + 20
	panel.Think = function(this)
		if (self.active) then
			this:SetAlpha(255)
		else
			this:SetAlpha((1 - math.TimeFraction(this.start, this.finish, CurTime())) * 255)
		end
	end

	self.list[#self.list + 1] = panel

	local class = CHAT_CLASS and CHAT_CLASS.filter and CHAT_CLASS.filter:lower() or "ic"

	if (ix.option.Get("chatFilter", ""):lower():find(class)) then
		self.filtered[panel] = class
		panel:SetVisible(false)
	else
		panel:SetPos(0, self.lastY)

		self.lastY = self.lastY + panel:GetTall()
		self.scroll:ScrollToChild(panel)
	end

	panel.filter = class

	return panel:IsVisible()
end

function PANEL:SetFilter(filter, state)
	if (state) then
		for _, v in ipairs(self.list) do
			if (v.filter == filter) then
				v:SetVisible(false)
				self.filtered[v] = filter
			end
		end
	else
		for k, v in pairs(self.filtered) do
			if (v == filter) then
				k:SetVisible(true)
				self.filtered[k] = nil
			end
		end
	end

	self.lastY = 0

	local lastChild

	for _, v in ipairs(self.list) do
		if (v:IsVisible()) then
			v:SetPos(0, self.lastY)
			self.lastY = self.lastY + v:GetTall() + 2
			lastChild = v
		end
	end

	if (IsValid(lastChild)) then
		self.scroll:ScrollToChild(lastChild)
	end
end

function PANEL:Think()
	if (gui.IsGameUIVisible() and self.active) then
		self.tabs:SetVisible(false)
		self:SetActive(false)
	end
end

vgui.Register("ixChatBox", PANEL, "DPanel")

if (IsValid(ix.gui.chat)) then
	RunConsoleCommand("fixchatplz")
end
