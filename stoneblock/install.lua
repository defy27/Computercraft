local base = "https://raw.githubusercontent.com/defy27/stoneblock/"

local files = {
    "mining.lua"
}

for _, file in ipairs(files) do
    print("Downloading " .. file)

    local response = http.get(base .. file)

    if response then
        local content = response.readAll()
        response.close()

        local output = fs.open(file, "w")
        output.write(content)
        output.close()

        print("Installed: " .. file)
    else
        print("Failed: " .. file)
    end
end

print("Installation complete!")
