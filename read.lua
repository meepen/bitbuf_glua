local config = include "./config.lua"
if (SERVER) then
    if (config.netstreamcompat) then
        util.AddNetworkString "BITBUF_NETSTREAM"
    end
    AddCSLuaFile()
end

local function bad(val, argn, name, err)
    if (not val) then
        error(("bad argument #%i to '%s' (%s)"):format(argn, name, err), 2)
    end
end

local mt = {
    __index = function(self, k)
      return getmetatable(self)[k]
    end,
    __call = function(self, data)
        return setmetatable({}, getmetatable(self)):Init(data)
    end
}

local function nop() end

local bb_read = setmetatable({
    SetupQueuedCallback = function(name, cb, filter)
        bad(isfunction(cb), 2, "SetupQueuedCallback", "expected function")
        local states = {}
        net.Receive(name, function(len, cl)
            states[cl] = states[cl] or {}
            local ID = net.ReadUInt(32)
            len = len - 32
            local state = states[cl][ID] or (function()
                len = len - 32
                local datalen = net.ReadUInt(32)
                ;(filter or nop)(cl, datalen)
                return {len = datalen, current = 0}
            end)()
            
            table.insert(state, net.ReadData(len / 8))
            
            states[cl][ID] = state
            state.current = state.current + len / 8
            if (state.current >= state.len) then
                states[cl][ID] = nil
                cb(table.concat(state), cl)
            end
        
            
        end)
    end
}, mt)

function mt:Init(data)
    bad(isstring(data), 1, "Init", "string expected")
    self:SetData(data)
    return self
end

function mt:SetData(data)
    self.Data = {}
    data:gsub("().", function(match)
        self.Data[match] = data:byte(match, match)
    end)
    self.Bits = 0
    self.Bytes = 1
    return self
end

function mt:Byte()
    return self:UInt(8)
end

function mt:String()
    local b = self:Byte()
    local dat = { n = 0 }
    while (b ~= 0) do
        dat[dat.n + 1] = string.char(b)
        dat.n = dat.n + 1
        b = self:Byte()
    end
    
    return table.concat(dat)
end

function mt:Int(totalbits)
    bad(isnumber(totalbits), 1, "Int", "number expected")
    bad(totalbits <= 32 and totalbits > 0, 1, "Int", "a number 1 through 32 expected")
    
    local retnum = 0
    
    for i = 1, totalbits, 8 do
        
        local bitsconsumed = i - 1
        local bits = math.min(totalbits - bitsconsumed, 8)
        local bitoffset = totalbits - bitsconsumed - bits
        
        local bitsleft = 8 - (self.Bits % 8)
        local byte = self.Bytes
        
        local bits1 = bits - bitsleft
        
        if (bits1 > 0) then -- need two byte
            
            local firstpart = bit.lshift(bit.band(2^bitsleft-1, self.Data[byte]), bits - bitsleft)
            local secondpart = bit.rshift(self.Data[byte + 1], 8 - bits + bitsleft)
            
            self.Bytes = self.Bytes + 1
            local part = firstpart + secondpart
            retnum = retnum + bit.lshift(part, bitoffset)
        else -- need one byte
            local part = bit.lshift(bit.rshift(self.Data[self.Bytes], -bits1), bitoffset)
            retnum = retnum + part
        end

        
        self.Bits = self.Bits + bits
        self.Bytes = math.ceil((self.Bits + 1) / 8)
        
    end
    return retnum
end

function mt:UInt(bits)
    local r = self:Int(bits)
    if (r < 0) then
        r = r + 0x100000000
    end
    return r
end

--[[ THE NEXT TWO FUNCTIONS ARE GIVEN RIGHTS TO ME FOR USAGE UNDER MIT LICENSE BY THE CREATOR ]]

local function UInt32sToDouble (low, high)
	local negative = false
	
	if high >= 0x80000000 then
		negative = true
		high = high - 0x80000000
	end
	
	local biasedExponent = bit.rshift (bit.band (high, 0x7FF00000), 20)
	local mantissa = (bit.band (high, 0x000FFFFF) * 4294967296 + low) / 2 ^ 52
	
	local f
	if biasedExponent == 0x0000 then
		f = mantissa == 0 and 0 or math.ldexp (mantissa, -1022)
	elseif biasedExponent == 0x07FF then
		f = mantissa == 0 and math.huge or (math.huge - math.huge)
	else
		f = math.ldexp (1 + mantissa, biasedExponent - 1023)
	end
	
	return negative and -f or f
end

local function UInt32ToFloat (n)
	-- 1 sign bit
	-- 8 biased exponent bits (bias of 127, biased value of 0 if 0 or denormal)
	-- 23 mantissa bits (implicit 1, unless biased exponent is 0)
	
	local negative = false
	
	if n >= 0x80000000 then
		negative = true
		n = n - 0x80000000
	end
	
	local biasedExponent = bit.rshift (bit.band (n, 0x7F800000), 23)
	local mantissa = bit.band (n, 0x007FFFFF) / (2 ^ 23)
	
	local f
	if biasedExponent == 0x00 then
		f = mantissa == 0 and 0 or math.ldexp (mantissa, -126)
	elseif biasedExponent == 0xFF then
		f = mantissa == 0 and math.huge or (math.huge - math.huge)
	else
		f = math.ldexp (1 + mantissa, biasedExponent - 127)
	end
	
	return negative and -f or f
end

function mt:Float()
    return UInt32ToFloat(self:UInt(32))
end

function mt:Double(dbl) 
    local low = self:UInt(32)
    local high = self:UInt(32)
    return UInt32sToDouble(low, high)
end

function mt:Write()
    
    net.Start(self.Name)
    
end

return bb_read