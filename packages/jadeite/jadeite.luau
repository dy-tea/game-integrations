-- jadeite v0.0.0
-- Copyright (C) 2025  Nikita Podvirnyi <krypt0nn@vk.com>, Dylan Donnell <dylan.donnell@student.griffith.ie>
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

local URL = "https://codeberg.org/mkrsym1/jadeite/releases/download/"

-- list of versions
local VERSIONS = {
    "v5.0.1",
    "v5.0.0",
    "v4.1.0",
    "v4.0.0",
    "v3.2.0",
    "v3.1.3",
    "v3.1.2",
    "v3.1.1",
    "v3.1.0",
    "v3.1.0",
    "v3.0.12",
    "v3.0.11",
    "v3.0.10",
    "v3.0.9",
    "v3.0.8",
    "v3.0.7",
    "v3.0.6",
    "v3.0.5",
    "v3.0.4",
    "v3.0.3",
    "v3.0.2",
    "v3.0.1",
    "v3.0.0",
    "v2.0.1",
    "v2.0.0",
    "v1.1.13",
    "v1.1.12",
    "v1.1.11",
    "v1.1.10",
    "v1.1.9",
    "v1.1.8",
    "v1.1.7",
    "v1.1.6",
    "v1.1.5",
    "v1.1.4",
    "v1.1.3",
    "v1.1.2",
    "v1.1.1",
    "v1.1.0",
    "v1.0.1",
    "v1.0.0",
}

type LaunchCommand = {
    binary: string,
    args: { string }?,
    env: { [string]: string }?
}

local data_dir_path: string = path.persist_dir("jadeite")

-- get the latest version
local function latest_version()
    return VERSIONS[1]
end

-- construct archive url for version
local function archive_url(version: string)
    return URL .. version .. "/" .. version .. ".zip"
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

        local original_binary = command.binary
        local original_args = command.args or {}

        local cmd = {
            binary = executable(ver),
            args = { original_binary },
            env = command.env or {}
        }

        for _, arg in ipairs(original_args) do
            table.insert(cmd.args, arg)
        end

        return cmd :: LaunchCommand
    end
}
