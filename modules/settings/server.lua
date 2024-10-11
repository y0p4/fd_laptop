local fakeNames = require 'data.fakeNames'
local fakeAvatars = require 'data.fakeAvatars'
local backgrounds = require 'config.backgrounds'
local framework = require 'bridge.framework'
local isProcessing

local function generateUsername()
    local username = ('%s%s'):format(fakeNames[math.random(1, #fakeNames)], math.random(1000, 9999))

    local result = MySQL.scalar.await('SELECT username FROM `fd_laptop` WHERE username = ?', { username })

    if result then
        return generateUsername()
    end

    return username
end

local function generateProfilePicture()
    return fakeAvatars[math.random(1, #fakeAvatars)]
end

local function loadUserSettings(identifier)
    if not identifier then return end

    local profile = MySQL.single.await([[
        SELECT
            *
        FROM
            `fd_laptop`
        WHERE
            identifier = ?
    ]], { identifier })

    if not profile then
        local username = generateUsername()
        local profile_picture = generateProfilePicture()
        local background = backgrounds[math.random(1, #backgrounds)].src

        MySQL.insert([[
            INSERT INTO
                `fd_laptop` (identifier, background, dark_mode, username, profile_picture)
            VALUES (
                ?,
                ?,
                ?,
                ?,
                ?
            )
        ]], {
            identifier,
            background,
            1,
            username,
            profile_picture
        }, function() end)

        isProcessing = false

        return {
            background = background,
            dark_mode = true,
            username = username,
            profile_picture = profile_picture,
            installedApps = {}
        }
    end

    isProcessing = false

    return {
        background = profile.background,
        dark_mode = profile.dark_mode,
        username = profile.username,
        profile_picture = profile.profile_picture,
        installedApps = profile.installedApps
    }
end
exports('getUserSettings', function(identifier)
    local userSettings = loadUserSettings(identifier)

    return userSettings
end)

---@return boolean | string[]
local function getInstalledApps(source)
    local identifier = framework.getIdentifier(source)

    if not identifier then
        return false
    end

    local installedApps = MySQL.scalar.await([[
        SELECT
            installedApps
        FROM
            `fd_laptop`
        WHERE
            identifier = ?
    ]], { identifier })

    if not installedApps then
        return false
    end

    return installedApps
end

local function saveAppearance(source, isDarkMode)
    local identifier = framework.getIdentifier(source)

    if not identifier then
        return false, locale('something_went_wrong')
    end

    MySQL.update([[
        UPDATE
            `fd_laptop`
        SET
            dark_mode = ?
        WHERE
            identifier = ?
    ]], {
        isDarkMode,
        identifier
    }, function() end)

    return true, nil
end

local function saveUserProfile(source, username, profilePicture)
    local identifier = framework.getIdentifier(source)

    if not identifier then
        return false, locale('something_went_wrong')
    end

    local currentProfile = MySQL.single.await([[
        SELECT
            username,
            profile_picture,
            (SELECT COUNT(username) FROM `fd_laptop` WHERE username = ?) AS usernameExists
        FROM
            `fd_laptop`
        WHERE
            identifier = ?
    ]], { username, identifier })

    if currentProfile.username ~= username and currentProfile.usernameExists > 0 then
        return false, 'Such username already exists'
    end

    username = username or currentProfile.username
    profilePicture = profilePicture or currentProfile.profile_picture

    MySQL.update([[
        UPDATE
            `fd_laptop`
        SET
            username = ?,
            profile_picture = ?
        WHERE
            identifier = ?
    ]], {
        username,
        profilePicture,
        identifier
    }, function() end)

    return true, nil
end

local function saveBackground(source, background)
    local identifier = framework.getIdentifier(source)

    if not identifier then
        return false, locale('something_went_wrong')
    end

    MySQL.update([[
        UPDATE
            `fd_laptop`
        SET
            background = ?
        WHERE
            identifier = ?
    ]], {
        background,
        identifier
    }, function() end)

    return true, nil
end

RegisterNetEvent('fd_laptop:server:playerLoaded', function()
    local src = source
    local identifier = framework.getIdentifier(src)

    if not identifier then
        return
    end

    if isProcessing then return end
    isProcessing = true

    local settings = loadUserSettings(identifier)

    ---@diagnostic disable-next-line: param-type-mismatch
    TriggerClientEvent('fd_laptop:client:settingsReady', src, settings)

    local installedApps = getInstalledApps(src)
    if installedApps then
        ---@diagnostic disable-next-line: param-type-mismatch
        TriggerClientEvent('fd_laptop:client:userInstalledApps', src, json.decode(installedApps))
    end

    isProcessing = false
end)

lib.callback.register('fd_laptop:server:updateAppearance', saveAppearance)
lib.callback.register('fd_laptop:server:updateBackground', saveBackground)
lib.callback.register('fd_laptop:server:updateProfile', saveUserProfile)
