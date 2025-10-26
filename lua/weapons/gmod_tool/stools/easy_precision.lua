TOOL.Category = "Construction"
TOOL.Name = "#tool.easy_precision.name"

TOOL.ClientConVar = {
    constraint_weld = "0",
    constraint_nocollide = "1",

    snap_divisions = "1",
    stick_cursor_to_grid = "1",

    grid_snap_x = "10",
    grid_snap_y = "10",
    grid_snap_z = "10",

    angle_snap_x = "45",
    angle_snap_y = "45",
    angle_snap_z = "45",
}

if CLIENT then
    TOOL.Information = {
        { name = "left", stage = 0 },
        { name = "left_1", stage = 1 },
        { name = "right", stage = 1 },
        { name = "reload" },
        { name = "reload_use", icon2 = "gui/e.png" }
    }
end

local IsValid = IsValid

local function SnapToGrid( value, gridSpacing )
    return math.Round( value / gridSpacing ) * gridSpacing
end

local function GetAABBSize( ent )
    local phys = ent:GetPhysicsObject()
    if not IsValid( phys ) then return end

    local mins, maxs = phys:GetAABB()
    if not mins or not maxs then return end

    return maxs - mins
end

local function IsValidEntity( ent )
    if not IsValid( ent ) then return false end
    if ent:IsPlayer() or ent:IsRagdoll() then return false end

    if SERVER then
        return GetAABBSize( ent ) ~= nil
    end

    return true
end

local function GetTraceEntity( trace )
    local ent = trace.Entity

    if IsValidEntity( ent ) then
        return ent
    end
end

local WorldToLocal = WorldToLocal
local LocalToWorld = LocalToWorld

function TOOL:GetNearestEdge( ent, aabbSize, worldPos )
    local snapDivisions = math.Clamp( self:GetClientNumber( "snap_divisions", 2 ), 1, 10 )

    -- Convert the position to the ent's local coords,
    -- using the bounding box center as the origin.
    local boxCenter = ent:LocalToWorld( ent:OBBCenter() )
    local pos = WorldToLocal( worldPos, Angle(), boxCenter, ent:GetAngles() )

    -- If the tool user is holding ALT, always return the bounding box center
    local user = self:GetOwner()

    if IsValid( user ) and user:KeyDown( IN_WALK ) then
        return boxCenter
    end

    -- Snap the local position to the nearest AABB edge
    local snapSize = aabbSize * ( 0.5 / snapDivisions )

    pos[1] = SnapToGrid( pos[1], snapSize[1] )
    pos[2] = SnapToGrid( pos[2], snapSize[2] )
    pos[3] = SnapToGrid( pos[3], snapSize[3] )

    -- Convert the snapped position back to world coords,
    -- also using the bounding box center as the origin.
    pos, _ = LocalToWorld( pos, Angle(), boxCenter, ent:GetAngles() )

    return pos
end

function TOOL:LeftClick( trace )
    local stage = self:GetStage()
    local ent = GetTraceEntity( trace )
    local success = false

    if stage == 0 and ent then
        success = true

        if SERVER then
            -- Get where the snapped cursor is placed on the entity
            local cursorPos = self:GetNearestEdge( ent, GetAABBSize( ent ), trace.HitPos )

            -- Remember the entity and where the cursor was on it
            self:SetObject( 1, ent, cursorPos, nil, 0, Vector( 0, 0, 1 ) )
            self:SetStage( 1 )
        end

    elseif stage == 1 then
        if SERVER then
            -- Find out where the cursor is right now
            local cursorPos = trace.HitPos

            if IsValid( ent ) then
                -- Snap cursor to the edge of the current entity being aimed at
                cursorPos = self:GetNearestEdge( ent, GetAABBSize( ent ), cursorPos )

            elseif self:GetClientNumber( "stick_cursor_to_grid", 0 ) > 0 then
                -- Snap cursor to grid, if enabled
                cursorPos[1] = SnapToGrid( cursorPos[1], self:GetClientNumber( "grid_snap_x", 10 ) )
                cursorPos[2] = SnapToGrid( cursorPos[2], self:GetClientNumber( "grid_snap_y", 10 ) )
                cursorPos[3] = SnapToGrid( cursorPos[3], self:GetClientNumber( "grid_snap_z", 10 ) )
            end

            -- Move the entity to the current cursor position, plus
            -- the cursor offset from when the entity was first selected.
            local selectedEnt = self:GetEnt( 1 )
            local firstCursorPos = self:GetPos( 1 )
            local offset = selectedEnt:GetPos() - firstCursorPos

            selectedEnt:SetPos( cursorPos + offset )

            local phys = selectedEnt:GetPhysicsObject()
            phys:EnableMotion( false )

            -- Apply constraints if we clicked on another entity
            if IsValid( ent ) and ent ~= selectedEnt then
                self:ApplyConstraints( selectedEnt, ent )
            end
        end

        self:ClearObjects()
        success = true
    end

    return success
end

function TOOL:RightClick()
    if self:GetStage() > 0 then
        self:ClearObjects()

        return true
    end
end

function TOOL:Reload( trace )
    local ent = GetTraceEntity( trace )

    if SERVER then
        local phys = ent:GetPhysicsObject()
        phys:EnableMotion( false )

        local user = self:GetOwner()

        if user:KeyDown( IN_USE ) then
            ent:SetAngles( Angle( 0, 0, 0 ) )
        else
            local ang = ent:GetAngles()

            ang[1] = SnapToGrid( ang[1], self:GetClientNumber( "angle_snap_x", 45 ) )
            ang[2] = SnapToGrid( ang[2], self:GetClientNumber( "angle_snap_y", 45 ) )
            ang[3] = SnapToGrid( ang[3], self:GetClientNumber( "angle_snap_z", 45 ) )

            ent:SetAngles( ang )
        end

        local pos = ent:GetPos()

        pos[1] = SnapToGrid( pos[1], self:GetClientNumber( "grid_snap_x", 10 ) )
        pos[2] = SnapToGrid( pos[2], self:GetClientNumber( "grid_snap_y", 10 ) )
        pos[3] = SnapToGrid( pos[3], self:GetClientNumber( "grid_snap_z", 10 ) )

        ent:SetPos( pos )
    end

    return IsValid( ent )
end

function TOOL:Deploy()
    self:ClearObjects()
    self.syncState = {}
end

function TOOL:Holster()
    self:ClearObjects()
    self.syncState = nil

    if CLIENT and IsValid( self.ghostEnt ) then
        self.ghostEnt:Remove()
        self.ghostEnt = nil
    end
end

if SERVER then
    util.AddNetworkString( "easy_precision.state" )

    function TOOL:ApplyConstraints( entA, entB )
        if not ( IsValid( entA ) and IsValid( entB ) ) then return end

        local user = self:GetOwner()
        if not user:CheckLimit( "constraints" ) then return end

        local doNoCollide = self:GetClientNumber( "constraint_nocollide", 0 ) > 0
        local doWeld = self:GetClientNumber( "constraint_weld", 0 ) > 0

        if doWeld then
            local c = constraint.Weld( entA, entB, 0, 0, 0, doNoCollide )
            if not IsValid( c ) then return end

            undo.Create( "Weld" )
            undo.SetPlayer( user )
            undo.AddEntity( c )
            undo.Finish()

            user:AddCount( "constraints", c )
            user:AddCleanup( "constraints", c )

        elseif doNoCollide then
            local c = constraint.NoCollide( entA, entB, 0, 0 )
            if not IsValid( c ) then return end

            undo.Create( "NoCollide" )
            undo.SetPlayer( user )
            undo.AddEntity( c )
            undo.Finish()

            user:AddCount( "constraints", c )
            user:AddCleanup( "nocollide", c )
        end
    end

    function TOOL:Think()
        local user = self:GetOwner()
        if not IsValid( user ) then return end

        local state = self.syncState
        if not state then return end

        -- The tool's client-side needs to know the server-side state,
        -- to place the cursor and ghost correctly on the screen.
        -- We send that state periodically in here, while
        -- trying to avoid spamming the net event.
        local t = RealTime()

        if state.isDirty and t > ( state.nextSync or 0 ) then
            state.isDirty = false
            state.nextSync = t + 0.2

            net.Start( "easy_precision.state", false )

            if IsValid( state.aimEnt ) then
                net.WriteEntity( state.aimEnt )

                local phys = state.aimEnt:GetPhysicsObject()
                local mins, maxs = phys:GetAABB()
                local size = maxs - mins

                net.WriteFloat( size[1] )
                net.WriteFloat( size[2] )
                net.WriteFloat( size[3] )
            else
                net.WriteEntity( NULL )
            end

            local selectedEnt = self:GetEnt( 1 )

            if IsValid( selectedEnt ) then
                net.WriteEntity( selectedEnt )

                local firstCursorPos = self:GetLocalPos( 1 )

                net.WriteFloat( firstCursorPos[1] )
                net.WriteFloat( firstCursorPos[2] )
                net.WriteFloat( firstCursorPos[3] )
            else
                net.WriteEntity( NULL )
            end

            net.Send( user )
        end

        local aimEnt = GetTraceEntity( user:GetEyeTrace() )

        if state.aimEnt ~= aimEnt then
            state.aimEnt = aimEnt
            state.isDirty = true
        end

        local selectedEnt = self:GetEnt( 1 )

        if state.selectedEnt ~= selectedEnt then
            state.selectedEnt = selectedEnt
            state.isDirty = true
        end
    end
end

if not CLIENT then return end

function TOOL.BuildCPanel( p )
    p:AddControl( "Header", { Description = "#tool.easy_precision.desc" } )

    p:AddControl( "CheckBox", { Label = "#tool.weld.name", Command = "easy_precision_constraint_weld" } )
    p:AddControl( "CheckBox", { Label = "#tool.nocollide", Command = "easy_precision_constraint_nocollide" } )

    p:AddControl( "Slider", { Label = "#tool.easy_precision.snap_divisions", Command = "easy_precision_snap_divisions", Min = 1, Max = 10 } )
    p:AddControl( "CheckBox", { Label = "#tool.easy_precision.stick_cursor_to_grid", Command = "easy_precision_stick_cursor_to_grid" } )

    p:AddControl( "Slider", { Label = "#tool.easy_precision.grid_snap_x", Command = "easy_precision_grid_snap_x", Type = "Float", Min = 0.1, Max = 1000 } )
    p:AddControl( "Slider", { Label = "#tool.easy_precision.grid_snap_y", Command = "easy_precision_grid_snap_y", Type = "Float", Min = 0.1, Max = 1000 } )
    p:AddControl( "Slider", { Label = "#tool.easy_precision.grid_snap_z", Command = "easy_precision_grid_snap_z", Type = "Float", Min = 0.1, Max = 1000 } )

    p:AddControl( "Slider", { Label = "#tool.easy_precision.angle_snap_x", Command = "easy_precision_angle_snap_x", Type = "Float", Min = 1, Max = 180 } )
    p:AddControl( "Slider", { Label = "#tool.easy_precision.angle_snap_y", Command = "easy_precision_angle_snap_y", Type = "Float", Min = 1, Max = 180 } )
    p:AddControl( "Slider", { Label = "#tool.easy_precision.angle_snap_z", Command = "easy_precision_angle_snap_z", Type = "Float", Min = 1, Max = 180 } )
end

net.Receive( "easy_precision.state", function()
    local tool = LocalPlayer():GetTool( "easy_precision" )
    if not tool then return end

    local state = tool.syncState

    if not state then
        -- It seems like "TOOL:Deploy" does not get called client-side
        -- if this tool is the first one being selected after the player spawned.
        -- This causes `syncState` to be `nil`, so this is a workaround.
        state = {}
        tool.syncState = state
    end

    state.aimEnt = net.ReadEntity()
    state.aimEntAABBSize = nil

    if IsValid( state.aimEnt ) then
        state.aimEntAABBSize = Vector(
            net.ReadFloat(),
            net.ReadFloat(),
            net.ReadFloat()
        )
    end

    state.selectedEnt = net.ReadEntity()

    if IsValid( state.selectedEnt ) then
        state.selectedEntFirstCursor = Vector(
            net.ReadFloat(),
            net.ReadFloat(),
            net.ReadFloat()
        )
    end
end )

local colors = {
    pivot = Color( 50, 50, 50 ),
    aim = Color( 0, 150, 255 ),
    selected = Color( 50, 255, 0 ),
    forceCenter = Color( 255, 150, 0 ),
}

local DrawLine = render.DrawLine

function TOOL:DrawHUD()
    local state = self.syncState
    if not state then return end

    local user = LocalPlayer()
    local trace = user:GetEyeTrace()

    local stage = self:GetStage()
    local cursorPos

    if IsValid( state.aimEnt ) and state.aimEnt == GetTraceEntity( trace ) then
        cursorPos = self:GetNearestEdge( state.aimEnt, state.aimEntAABBSize, trace.HitPos )

    elseif stage > 0 then
        cursorPos = trace.HitPos

        if self:GetClientNumber( "stick_cursor_to_grid", 0 ) > 0 then
            cursorPos[1] = SnapToGrid( cursorPos[1], self:GetClientNumber( "grid_snap_x", 10 ) )
            cursorPos[2] = SnapToGrid( cursorPos[2], self:GetClientNumber( "grid_snap_y", 10 ) )
            cursorPos[3] = SnapToGrid( cursorPos[3], self:GetClientNumber( "grid_snap_z", 10 ) )
        end
    end

    if cursorPos then
        local pulse = 0.6 + math.sin( RealTime() * 8 ) * 0.4
        local color = stage > 0 and colors.selected or colors.aim

        if user:KeyDown( IN_WALK ) then
            color = colors.forceCenter
        end

        cam.Start3D()
        render.SetColorMaterialIgnoreZ()
        render.SetColorModulation( 0, pulse * 0.3, pulse )
        render.SuppressEngineLighting( true )

        render.DrawSphere( cursorPos, 1.5, 6, 6, colors.pivot )
        render.DrawSphere( cursorPos, 1, 6, 6, color )

        local offset = Vector( 15, 0, 0 )
        DrawLine( cursorPos - offset, cursorPos + offset, color, false )

        offset[1] = 0
        offset[2] = 15
        DrawLine( cursorPos - offset, cursorPos + offset, color, false )

        offset[2] = 0
        offset[3] = 15
        DrawLine( cursorPos - offset, cursorPos + offset, color, false )

        render.SuppressEngineLighting( false )
        render.SetColorModulation( 1, 1, 1 )
        cam.End3D()
    end

    local selectedEnt = state.selectedEnt

    if cursorPos and IsValid( selectedEnt ) then
        local localCursorPos = selectedEnt:WorldToLocal( cursorPos )

        local pos = selectedEnt:LocalToWorld( localCursorPos - state.selectedEntFirstCursor )
        local ang = selectedEnt:GetAngles()

        if IsValid( self.ghostEnt ) then
            self.ghostEnt:SetPos( pos )
            self.ghostEnt:SetAngles( ang )
        else
            self.ghostEnt = ClientsideModel( selectedEnt:GetModel() )
            self.ghostEnt:SetPos( pos )
            self.ghostEnt:SetAngles( ang )
            self.ghostEnt:Spawn()

            self.ghostEnt:SetColor( colors.selected )
            self.ghostEnt:SetRenderMode( RENDERMODE_NORMAL )
            self.ghostEnt:SetMaterial( "models/wireframe" )
            self.ghostEnt:DrawShadow( false )
        end

    elseif IsValid( self.ghostEnt ) then
        self.ghostEnt:Remove()
    end
end
