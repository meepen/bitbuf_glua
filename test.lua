if (SERVER) then
    local bb_read = include "bitbuf/read.lua"
    bb_read.SetupQueuedCallback("weapon_smg1", function(data, pl)
        local read = bb_read(data)
        local amount = read:UInt(12)
        print (pl:Nick().." has sent us "..amount.." numbers:")
        for i = 1, amount do
            print(read:Double())
        end
    end)
end

if (CLIENT) then
    local bb_write = include "bitbuf/write.lua"
    
    local write = bb_write()
    local amount = math.random(0xF00, 0xFFF)
    write:UInt(amount, 12)
    for i = 1, amount do
        write:Double(math.random(100,200) / 100)
    end
    write:QueuedWrite("weapon_smg1", 20600, net.SendToServer)
end