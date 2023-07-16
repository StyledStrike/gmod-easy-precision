TOOL.Category = "Construction"
TOOL.Name = "#tool.easy_precision.name"

TOOL.ClientConVar = {
    follow_grid = "0",
    grid_x = "10",
    grid_y = "10",
    grid_z = "1",
    nocollide = "1",
    weld = "0"
}

if CLIENT then
    TOOL.Information = {
        { name = "left", stage = 0 },
        { name = "left_1", stage = 1 },
        { name = "right", stage = 1 },
        { name = "reload" }
    }

    language.Add( "tool.easy_precision.name", "Easy Precision" )
    language.Add( "tool.easy_precision.desc", "Precisely move a prop to another with just two clicks" )

    language.Add( "tool.easy_precision.left", "Select an object to move" )
    language.Add( "tool.easy_precision.left_1", "Move object here" )
    language.Add( "tool.easy_precision.right", "Cancel" )
    language.Add( "tool.easy_precision.reload", "Snap a object's position/rotation to the grid" )

    language.Add( "tool.easy_precision.follow_grid", "Snap cursor to the grid (Only applies to the world)" )
    language.Add( "tool.easy_precision.grid_x", "Grid Size (X)" )
    language.Add( "tool.easy_precision.grid_y", "Grid Size (Y)" )
    language.Add( "tool.easy_precision.grid_z", "Grid Size (Z)" )

    language.Add( "tool.easy_precision.grid_z.help", [[The grid size has an effect on:
- The Reload button
- The cursor, if "Snap cursor to the grid" is enabled]] )
end

local function Snap( num, grid )
    return math.Round( num / grid ) * grid
end

local function GetAABBSize( ent )
    local ret, ret2 = ent:GetPhysicsObject():GetAABB()
    ret = ret or vector_origin
    ret2 = ret2 or vector_origin
    return ret2 - ret
end

local function GetCursorPosOnEntity( ent, from )
    -- convert "from" to the ent's local coords,
    -- but using the bounding box center as the origin

    local boxCenter = ent:LocalToWorld( ent:OBBCenter() )
    local pos, _ = WorldToLocal( from, angle_zero, boxCenter, ent:GetAngles() )

    local size = GetAABBSize( ent )
    local snapSize = size * 0.5

    pos.x = Snap( pos.x, snapSize.x )
    pos.y = Snap( pos.y, snapSize.y )
    pos.z = Snap( pos.z, snapSize.z )

    -- convert the local pos to world,
    -- but using the bounding box center as the origin
    pos, _ = LocalToWorld( pos, angle_zero, boxCenter, ent:GetAngles() )

    return pos
end

local function GetTraceEntity( trace )
    local ent = trace.Entity

    if IsValid( ent ) and not ent:IsPlayer() and not ent:IsRagdoll() then
        local phys = ent:GetPhysicsObject()

        if IsValid( phys ) then
            return ent
        end
    end
end

function TOOL:GetCursorPos()
    local trace = self:GetOwner():GetEyeTrace()

    if trace.Hit then
        local pos = trace.HitPos
        local ent = GetTraceEntity( trace )

        if IsValid( ent ) then
            pos = GetCursorPosOnEntity( ent, pos )

        elseif self:GetClientNumber( "follow_grid", 0 ) > 0 then
            pos.x = Snap( pos.x, self:GetClientNumber( "grid_x", 10 ) )
            pos.y = Snap( pos.y, self:GetClientNumber( "grid_y", 10 ) )
            pos.z = Snap( pos.z, self:GetClientNumber( "grid_z", 1 ) )
        end

        return pos
    end

    return trace.StartPos
end

function TOOL:SetCursorColor( color )
    if IsValid( self.cursorEnt ) then
        self.cursorEnt:SetColor( color )
    end
end

function TOOL:ResetStage()
    self:SetStage( 0 )

    if SERVER then
        if IsValid( self.moveGhost ) then
            self.moveGhost:Remove()
        end

        self.moveGhost = nil
        self.moveEntity = nil
        self.moveOffset = nil
        self.moveAngles = nil

        self:SetCursorColor( color_white )
    end
end

function TOOL:ApplyConstraints( ent1, ent2 )
    if not ( IsValid( ent1 ) and IsValid( ent2 ) ) then return end

    local nocollide = self:GetClientNumber( "nocollide", 0 ) > 0
    local weld = self:GetClientNumber( "weld", 0 ) > 0

    if weld then
        local constr = constraint.Weld( ent1, ent2, 0, 0, 0, nocollide )

        if IsValid( constr ) then
            undo.Create( "Weld" )
            undo.AddEntity( constr )
            undo.SetPlayer( self:GetOwner() )
            undo.Finish()

            self:GetOwner():AddCleanup( "constraints", constr )
        end

    elseif nocollide then
        local constr = constraint.NoCollide( ent1, ent2, 0, 0 )

        if IsValid( constr ) then
            undo.Create( "NoCollide" )
            undo.AddEntity( constr )
            undo.SetPlayer( self:GetOwner() )
            undo.Finish()

            self:GetOwner():AddCleanup( "nocollide", constr )
        end
    end
end

function TOOL:Think()
    if self.moveEntity and not IsValid( self.moveEntity ) then
        self:ResetStage()
        return
    end

    if not SERVER then return end

    local cursorPos = self:GetCursorPos()

    if IsValid( self.cursorEnt ) then
        self.cursorEnt:SetPos( cursorPos )
    end

    if IsValid( self.moveGhost ) then
        local localCursor = self.moveGhost:WorldToLocal( cursorPos )
        local offset = localCursor - self.moveOffset

        self.moveGhost:SetPos( self.moveGhost:LocalToWorld( offset ) )
    end
end

function TOOL:Deploy()
    -- we dont use the cursor clientside because
    -- its location might depend on a physobj
    if SERVER then
        local ent = ents.Create( "prop_physics" )
        if not IsValid( ent ) then return end

        ent:SetModel( "models/editor/axis_helper.mdl" )
        ent:SetPos( Vector() )
        ent:SetAngles( angle_zero )
        ent:Spawn()

        ent:PhysicsDestroy()
        ent:SetMoveType( MOVETYPE_NONE )
        ent:SetNotSolid( true )
        ent:SetRenderMode( RENDERMODE_NORMAL )
        ent:SetMaterial( "debug/debugdrawflat" )
        ent:SetColor( color_white )
        ent:DrawShadow( false )

        self.cursorEnt = ent
    end
end

function TOOL:Holster()
    self:ResetStage()

    if SERVER then
        if IsValid( self.cursorEnt ) then
            self.cursorEnt:Remove()
        end

        self.cursorEnt = nil
    end
end

function TOOL:LeftClick( trace )
    local stage = self:GetStage()
    local ent = GetTraceEntity( trace )

    if stage > 0 then
        if SERVER then
            local localCursor = self.moveEntity:WorldToLocal( self:GetCursorPos() )
            local offset = localCursor - self.moveOffset

            self.moveEntity:SetPos( self.moveEntity:LocalToWorld( offset ) )
            self.moveEntity:SetAngles( self.moveAngles )

            self:ApplyConstraints( self.moveEntity, ent )
        end

        self:ResetStage()

        return true
    end

    if not ent then
        -- almost correct feedback on the client
        if CLIENT and IsValid( trace.Entity ) then
            return true
        end

        return
    end

    self:SetStage( 1 )

    if SERVER then
        local cursorPos = GetCursorPosOnEntity( ent, trace.HitPos )
        local offset = ent:WorldToLocal( cursorPos )

        local ghost = ents.Create( "prop_physics" )
        ghost:SetModel( ent:GetModel() )
        ghost:SetPos( ent:GetPos() )
        ghost:SetAngles( ent:GetAngles() )
        ghost:Spawn()

        ghost:PhysicsDestroy()
        ghost:SetMoveType( MOVETYPE_NONE )
        ghost:SetNotSolid( true )
        ghost:SetRenderMode( RENDERMODE_TRANSCOLOR )
        ghost:SetMaterial( "debug/debugdrawflat" )
        ghost:SetColor( Color( 255, 255, 255, 50 ) )
        ghost:DrawShadow( false )

        self.moveGhost = ghost
        self.moveEntity = ent
        self.moveOffset = offset
        self.moveAngles = ent:GetAngles()

        self:SetCursorColor( Color( 0, 255, 255 ) )
    end

    return true
end

function TOOL:RightClick()
    if self:GetStage() > 0 then
        self:ResetStage()

        return true
    end
end

function TOOL:Reload( trace )
    local ent = GetTraceEntity( trace )

    if not ent then
        -- almost correct feedback on the client
        if CLIENT and IsValid( trace.Entity ) then
            return true
        end

        return
    end

    if SERVER then
        local phys = ent:GetPhysicsObject()

        if IsValid( phys ) then
            phys:EnableMotion( false )
        end

        local ang = ent:GetAngles()

        ent:SetAngles( Angle(
            Snap( ang.pitch, 10 ),
            Snap( ang.yaw, 10 ),
            Snap( ang.roll, 10 )
        ) )

        local pos = ent:GetPos()

        pos.x = Snap( pos.x, self:GetClientNumber( "grid_x", 10 ) )
        pos.y = Snap( pos.y, self:GetClientNumber( "grid_y", 10 ) )
        pos.z = Snap( pos.z, self:GetClientNumber( "grid_z", 1 ) )

        ent:SetPos( pos )
    end

    return true
end

if not CLIENT then return end

function TOOL.BuildCPanel( p )
    p:AddControl( "Header", { Description = "#tool.easy_precision.desc" } )
    p:AddControl( "CheckBox", { Label = "#tool.easy_precision.follow_grid", Command = "easy_precision_follow_grid" } )

    p:AddControl( "Slider", { Label = "#tool.easy_precision.grid_x", Command = "easy_precision_grid_x", Type = "Float", Min = 0.01, Max = 1000 } )
    p:AddControl( "Slider", { Label = "#tool.easy_precision.grid_y", Command = "easy_precision_grid_y", Type = "Float", Min = 0.01, Max = 1000 } )
    p:AddControl( "Slider", { Label = "#tool.easy_precision.grid_z", Command = "easy_precision_grid_z", Type = "Float", Min = 0.01, Max = 1000, Help = true } )

    p:AddControl( "CheckBox", { Label = "#tool.nocollide", Command = "easy_precision_nocollide" } )
    p:AddControl( "CheckBox", { Label = "#tool.weld.name", Command = "easy_precision_weld" } )
end

local GRID = {
    color = Color( 50, 100, 255 ),
    points = 3
}

function TOOL:DrawHUD()
    local tr = LocalPlayer():GetEyeTrace()
    if not tr.Hit then return end
    if IsValid( tr.Entity ) then return end
    if self:GetClientNumber( "follow_grid", 0 ) == 0 then return end

    local pos = tr.HitPos

    local gridX = self:GetClientNumber( "grid_x", 10 )
    local gridY = self:GetClientNumber( "grid_y", 10 )
    local gridZ = self:GetClientNumber( "grid_z", 1 )

    pos.x = Snap( pos.x, gridX * GRID.points * 2 )
    pos.y = Snap( pos.y, gridY * GRID.points * 2 )
    pos.z = Snap( pos.z, gridZ * GRID.points )

    cam.Start3D()

    local tall = gridY * GRID.points

    for x = -GRID.points, GRID.points do
        render.DrawLine(
            pos + Vector( x * gridX, -tall, 0 ),
            pos + Vector( x * gridX, tall, 0 ),
            GRID.color, true
        )
    end

    local wide = gridX * GRID.points

    for y = -GRID.points, GRID.points do
        render.DrawLine(
            pos + Vector( -wide, y * gridY, 0 ),
            pos + Vector( wide, y * gridY, 0 ),
            GRID.color, true
        )
    end

    cam.End3D()
end
