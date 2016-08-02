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
    __call = function(self, name)
        return setmetatable({}, getmetatable(self)):Init()
    end
}

local bb_write = setmetatable({}, mt)

function mt:Init()
    self:ResetData()
    return self
end

function mt:ResetData()
    self.Data = {0, n = 1}
    self.Bits = 0
    self.Bytes = 1
    return self
end

function mt:Byte(b)
    bad(isnumber(b), 1, "Byte", "number expected")
    bad(b >= 0 and b <= 0xFF, 1, "Byte", "byte expected")
    self:Int(b, 8)
    return self
end

function mt:String(str)
    bad(isstring(str), 1, "String", "string expected")
    for i = 1, str:len() do
        self:Byte(str:byte(i, i))
    end
    self:Byte(0)
    return self
end

function mt:Int(num, totalbits)
    bad(isnumber(num), 1, "Int", "number expected")
    bad(isnumber(totalbits), 2, "Int", "number expected")
    bad(totalbits <= 32 and totalbits > 0, 2, "Int", "a number 1 through 32 expected")
    
    for i = 1, totalbits, 8 do
        
        local bitsconsumed = i - 1
        local bits = math.min(totalbits - bitsconsumed, 8)
        local b = bit.band(2^(bits) - 1, bit.rshift(num, totalbits - bitsconsumed - bits))
        
        local bitsleft = 8 - (self.Bits % 8)
        local byte = self.Bytes
        
        local bits1 = bits - bitsleft
        
        if (bits1 > 0) then -- need two byte
            
            local firstpart = bit.rshift(b, bits - bitsleft)
            local secondpart = bit.band(bit.lshift(b, 8 - (bits - bitsleft)), 0xFF)
            self.Data[byte] = bit.bor(firstpart, self.Data[byte])
            
            self.Bytes = self.Bytes + 1
            self:EnsureBytes(self.Bytes)
            self.Data[byte + 1] = secondpart
        else -- need one byte
            self.Data[byte] = bit.bor(self.Data[byte], bit.band(0xFF, bit.lshift(b, -bits1)))
        end

        
        self.Bits = self.Bits + bits
        self.Bytes = math.ceil((self.Bits + 1) / 8)
        self:EnsureBytes(self.Bytes)
        
    end
    return self
end

function mt:UInt(num, bits)
    return self:Int(num, bits)
end


function mt:EnsureBytes(n)
    for i = self.Data.n + 1, n do
        self.Data[i] = 0
    end
    
    self.Data.n = math.max(self.Data.n, n)
    return self
end

--[[ THE NEXT TWO FUNCTIONS ARE GIVEN RIGHTS TO ME FOR USAGE UNDER MIT LICENSE BY THE CREATOR ]]
local function DoubleToUInt32s (f)
	-- 1 / f is needed to check for -0
	local high = 0
	local low  = 0
	if f < 0 or 1 / f < 0 then
		high = high + 0x80000000
		f = -f
	end
	
	local mantissa = 0
	local biasedExponent = 0
	
	if f == math.huge then
		biasedExponent = 0x07FF
	elseif f ~= f then
		biasedExponent = 0x07FF
		mantissa = 1
	elseif f == 0 then
		biasedExponent = 0x00
	else
		mantissa, biasedExponent = math.frexp (f)
		biasedExponent = biasedExponent + 1022
		
		if biasedExponent <= 0 then
			-- Denormal
			mantissa = math.floor (mantissa * 2 ^ (52 + biasedExponent) + 0.5)
			biasedExponent = 0
		else
			mantissa = math.floor ((mantissa * 2 - 1) * 2 ^ 52 + 0.5)
		end
	end
	
	low = mantissa % 4294967296
	high = high + bit.lshift (bit.band (biasedExponent, 0x07FF), 20)
	high = high + bit.band (math.floor (mantissa / 4294967296), 0x000FFFFF)
	
	return low, high
end

local function FloatToUInt32 (f)
	-- 1 / f is needed to check for -0
	local n = 0
	if f < 0 or 1 / f < 0 then
		n = n + 0x80000000
		f = -f
	end
	
	local mantissa = 0
	local biasedExponent = 0
	
	if f == math.huge then
		biasedExponent = 0xFF
	elseif f ~= f then
		biasedExponent = 0xFF
		mantissa = 1
	elseif f == 0 then
		biasedExponent = 0x00
	else
		mantissa, biasedExponent = math.frexp (f)
		biasedExponent = biasedExponent + 126
		
		if biasedExponent <= 0 then
			-- Denormal
			mantissa = math.floor (mantissa * 2 ^ (23 + biasedExponent) + 0.5)
			biasedExponent = 0
		else
			mantissa = math.floor ((mantissa * 2 - 1) * 2 ^ 23 + 0.5)
		end
	end
	
	n = n + bit.lshift (bit.band (biasedExponent, 0xFF), 23)
	n = n + bit.band (mantissa, 0x007FFFFF)
	
	return n
end

function mt:Float(flt)
    bad(isnumber(flt), 1, "Float", "expected number")
    
    self:UInt(FloatToUInt32(flt), 32)
    return self
end

function mt:Double(dbl)
    bad(isnumber(dbl), 1, "Double", "expected number")
    local low, high = DoubleToUInt32s(dbl)
    self:UInt(low, 32)
    self:UInt(high, 32)
    return self
end

local function nop() end
local SHARED_ID = 0
function mt:QueuedWrite(name, split, sendfn)
    bad(isstring(name) and util.NetworkStringToID(name) ~= 0, 1, "QueuedWrite", "a networked string")
    bad(split > 0 and split <= 46000, 2, "QueuedWrite", "a number 1 to 46000 expected")
    bad(isfunction(sendfn), 3, "QueuedWrite", "function expected")
    local datapertick = math.floor(engine.TickInterval() * split)
    local offset = 1
    local id = SHARED_ID 
    local TIMER_ID = "QUEUEDWRITE_"..name.."_BITBUF"
    SHARED_ID = SHARED_ID + 1
    local function tick(fn)
        net.Start(name)
            net.WriteUInt(id, 32)
            ;(fn or nop)()
            local start = offset
            local ends = math.min(self.Data.n, offset + datapertick - 2)
            net.WriteData(string.char(unpack(self.Data, start, ends)), ends - start + 1)
            offset = offset + datapertick - 1
        sendfn()
        if (offset > self.Data.n) then
            timer.Remove(TIMER_ID)
        end
    end
            
    timer.Create(TIMER_ID, engine.TickInterval(), 0, tick)
    tick(function()
        net.WriteUInt(self.Bytes, 32)
    end)
end

function mt:ExportAsString()
    local d = {}
    for i = 1, self.Data.n do
        d[i] = string.char(self.Data[i])
    end
    return table.concat(d)
end

return bb_write