local InfoPanel = table.Copy(vgui.GetControlTable("DPanel"))

local cfpnls = {
    bool = function(id, key, data)
        local val = menup.config.get(id, key, isbool(data[3]) and data[3] or false)
        local root = vgui.Create("DPanel")
        local label = root:Add("DLabel")
        local cb = root:Add("DCheckBox")
        if isstring(data[4]) then root:SetTooltip(data[4]) end
        cb:Dock(RIGHT)
        cb:SetWide(15)
        cb:SetChecked(val)
        label:Dock(FILL)
        label:SetText(data[1])
        label:SetTextColor(Color(0, 0, 0))
        cb.OnChange = function(pnl, newval)
            menup.config.set(id, key, newval)
        end
        return root
    end,
    int = function(id, key, data)
        local val = menup.config.get(id, key, isnumber(data[3]) and data[3] or 0)
        local root = vgui.Create("DPanel")
        local label = root:Add("DLabel")
        local wang = root:Add("DNumberWang")
        if isstring(data[4]) then root:SetTooltip(data[4]) end
        wang:Dock(RIGHT)
        wang:SetDecimals(0)
        wang:SetMin(-math.huge)
        wang:SetMax(math.huge)
        wang:SetValue(val)
        label:Dock(FILL)
        label:SetText(data[1])
        label:SetTextColor(Color(0, 0, 0))
        wang.OnValueChanged = function(pnl, newval)
            newval = math.Round(newval)
            wang:SetText(tostring(newval))
            menup.config.set(id, key, newval)
        end
        return root
    end,
}

function InfoPanel:Init()
    self:SetTall(512)
    self:SetPaintBackground(false)
    local controls = self:Add("DPanel")
    controls:SetPaintBackground(false)
    controls:Dock(TOP)
    controls:SetTall(36)
    local toggle = controls:Add("DButton")
    local alt = controls:Add("DButton")
    local md = self:Add("MarkdownPanel")
    local cp = self:Add("DScrollPanel")
    md:SetPos(0, 32)
    md:SetTall(512)
    cp:SetPos(self:GetWide(), 32)
    cp:SetTall(512)
    self.controls = controls
    self.toggle = toggle
    self.alt = alt
    self.md = md
    self.cp = cp
    self.scroll = 1
end

function InfoPanel:Think()
    local w = self.controls:GetWide()
    local h = self:GetParent():GetParent():GetParent():GetTall() - 56 -- info collapse list sheet frame
    local s = self.scroll
    self.toggle:SetWide(w / 2)
    self.alt:SetWide(w / 2)
    self.md:SetSize(w, h)
    self.cp:SetSize(w, h)
    self.alt:SetPos(w / 2, 0)
    self.md:SetPos(-w * s, 32)
    self.cp:SetPos((1 - s) * w, 32)
end

function InfoPanel:SetEnabled(state)
    local plugs = util.JSONToTable(menup.db.get("enabled", "{}"))
    local manifest = self.manifest
    manifest.enabled = state
    plugs[manifest.id] = state
    menup.db.set("enabled", util.TableToJSON(plugs, false))
    if state then
        local success, result = pcall(manifest.func)
        if not success then
            ErrorNoHalt("Error loading " .. manifest.id .. ":\n" .. result)
        elseif isfunction(result) then
            manifest.undo = result
        else
            manifest.undo = function() end
        end
    else manifest.undo() end
    self:GetParent().toggle:SetChecked(state)
    self:Load(manifest)
end

function InfoPanel:BuildConfig(manifest)
    self.cp:Clear()
    print("building config for " .. manifest.id)
    for k, v in pairs(manifest.config) do -- name type param desc
        if isfunction(cfpnls[v[2]]) then
            local pnl = cfpnls[v[2]](manifest.id, k, v)
            self.cp:AddItem(pnl)
            pnl:Dock(TOP)
            pnl:DockPadding(4, 4, 4, 4)
            pnl:DockMargin(0, 2, 0, 2)
        else
            print(manifest.id .. " has unknown config type \"" .. v[2] .. "\" for key \"" .. k .. "\"!")
        end
    end
end

function InfoPanel:Load(manifest)
    self.manifest = manifest
    self.md:SetMarkdown(string.format([[
## %s
%s  
## 
*Author* : %s  
*Version* : %s  
*ID* : `%s`  
*File* : `%s`  
]], manifest.name, manifest.description, manifest.author, manifest.version, manifest.id, manifest.file))
    if manifest.enabled and not table.IsEmpty(manifest.config) then self:BuildConfig(manifest) end
    if manifest.enabled then
        self.toggle:SetText("Disable")
        self.toggle:SetIcon("icon16/delete.png")
        self.alt:SetText("Config")
        self.alt:SetIcon("icon16/cog.png")
        self.alt:SetEnabled(!table.IsEmpty(manifest.config))
    else
        self.toggle:SetText("Enable")
        self.toggle:SetIcon("icon16/add.png")
        self.alt:SetText("Reset")
        self.alt:SetIcon("icon16/control_repeat.png")
        self.alt:SetEnabled(true)
    end
    self.toggle.DoClick = function() self:SetEnabled(!manifest.enabled) end
end

local PANEL = {}

function PANEL:Init()
    local new, legacy = {}, {}
    local lcollapse
    self.plugins = {}

    self:SetPaintBackground(false)

    for _, v in SortedPairsByMemberValue(menup.plugins, "name") do
        if v.legacy then table.insert(legacy, v)
        else table.insert(new, v) end
    end

    for _, v in ipairs(new) do
        local collapse = self:Add("     " .. v.name)
        local toggle = collapse.Header:Add("DCheckBox")
        toggle:SetPos(2, 2)
        toggle:SetChecked(v.enabled)
        local info = vgui.CreateFromTable(InfoPanel, collapse)
        collapse:SetContents(info)
        collapse:SetExpanded(false)
        function collapse.OnToggle(me, state)
            if !state then return end
            for _, c in pairs(self:GetChildren()[1]:GetChildren()) do
                if c ~= me then c:DoExpansion(false) end
            end
            timer.Simple(me:GetAnimTime(), function() self:ScrollToChild(collapse) end)
        end
        function toggle:OnChange(state)
            info:SetEnabled(state)
        end
        info:Load(v)
        collapse.toggle = toggle
        collapse.info = info
        self.plugins[v.id] = collapse
    end

    if !table.IsEmpty(legacy) then
        lcollapse = self:Add("Legacy plugins")
        lcollapse:SetExpanded(false)
        function lcollapse.OnToggle(me, state)
            if !state then return end
            for _, c in pairs(self:GetChildren()[1]:GetChildren()) do
                if c ~= me then c:DoExpansion(false) end
            end
            timer.Simple(me:GetAnimTime(), function() self:ScrollToChild(lcollapse) end)
        end

        for _, v in ipairs(legacy) do
            local btn = lcollapse:Add(v.name)
        end
    end
end

function PANEL:Paint() end

vgui.Register("PluginsPanel", PANEL, "DCategoryList")