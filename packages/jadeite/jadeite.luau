-- jadeite v0.0.0
-- Copyright (C) 2025  Dylan Donnell <dylan.donnell@student.griffith.ie>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

local URL = "https://codeberg.org/mkrsym1/jadeite/releases/"

type LaunchCommand = {
    binary: string,
    args: { string }?,
    env: { [string]: string }?
}

local data_dir_path: string = path.persist_dir("jadeite")

-- get the latest version
local function latest_version()
    local resp = net.fetch(URL .. "latest")

    if resp.is_ok then
        local body = str.from_bytes(resp.body)
        local match = body:match('"tag/(.-)"')
        if match then
            dbg(`jadeite - latest version: {match}`)
            return match
        end
    end

    error(`jadeite - no latest version found`)
    return ""
end

-- construct archive url for version
local function archive_url(version: string)
    return URL .. "download/" .. version .. "/" .. version .. ".zip"
end

-- download and extract specified version
local function fetch(version: string)
    local archive_path = path.join(path.temp_dir(), version .. ".zip")

    -- download
    local downloader_handle = downloader.create()
    local task_handle = downloader.download(downloader_handle, {
        url = archive_url(version),
        output_file = archive_path
    })
    downloader.wait(task_handle)
    downloader.close(downloader_handle)

    -- extract
    local archive_handle = archive.open(archive_path)
    fs.create_dir(path.join(data_dir_path, version))
    archive.extract(archive_handle, path.join(data_dir_path, version))
    archive.close(archive_handle)

    -- remove archive
    fs.remove(archive_path)
end

local function executable(version: string)
    return path.join(data_dir_path, version, "jadeite.exe")
end

local function init(version: string?)
    local ver = version or latest_version()
    if not fs.exists(path.join(data_dir_path, ver)) then
        fetch(ver)
    end
end

return {
    init = init,
    wrap_launch_command = function(command: LaunchCommand, version: string?): LaunchCommand
        local ver = version or latest_version()
        init(ver)

        -- args will be args to jadeite
        -- game path, launcher path, game args
        local args = { command.binary, "--" }
        if command.args then
            for _, arg in ipairs(command.args) do
                table.insert(args, arg)
            end
        end

        local cmd = {
            binary = executable(ver),
            args = args,
            env = command.env or {}
        }

        return cmd :: LaunchCommand
    end
}
