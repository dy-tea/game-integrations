-- settings v0.0.0
-- Copyright (C) 2025  Nikita Podvirnyi <krypt0nn@vk.com>
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

--!nocheck

type Localizable = string | { [string]: string }

type GameVariant = {
    platform: string,
    edition: string
}

-------------------------------- Builder layout types --------------------------------

type EntryReactivity = "none" | "relaxed" | "release"

type BuilderEntryOptions = {
    -- Call this function before returning settings value.
    get: ((value: any) -> any)?,

    -- Call this function before updating settings value.
    set: ((value: any) -> any)?
}

type BuilderOptions = {
    game: string,
    layout: { [string]: BuilderGroupLayout }
}

type BuilderGroupLayout = {
    title: Localizable?,
    description: Localizable?,
    entries: { [string]: BuilderEntryLayout }
}

type BuilderEntryLayout = {
    title: Localizable,
    description: Localizable?,
    reactivity: EntryReactivity?,

    entry: {
        format: "switch" | "text" | "enum" | "expandable",
        default: any,

        -- enum
        values: { [string]: Localizable }?,

        -- expandable
        entries: { BuilderEntryLayout }?
    },

    options: BuilderEntryOptions?
}

-------------------------------- Actual layout types --------------------------------

type GroupLayout = {
    title: Localizable?,
    description: Localizable?,
    entries: { EntryLayout }
}

type EntryLayout = {
    name: string?,
    title: Localizable,
    description: Localizable?,
    reactivity: EntryReactivity?,
    entry: { EntryFormat }
}

type EntryFormat =
    | EntryFormatSwitch
    | EntryFormatText
    | EntryFormatEnum
    | EntryFormatExpandable

type EntryFormatSwitch = {
    format: "switch",
    value: string
}

type EntryFormatText = {
    format: "text",
    value: string
}

type EntryFormatEnum = {
    format: "enum",
    values: { [string]: Localizable },
    selected: string
}

type EntryFormatExpandable = {
    format: "expandable",
    entries: { EntryFormat }
}

-------------------------------- Module --------------------------------

local function serialize(value: any): string?
    if typeof(value) == "string" then
        return `s:{value}`
    elseif typeof(value) == "number" then
        return `n:{value}`
    elseif typeof(value) == "boolean" then
        if value then
            return "b:1"
        else
            return "b:0"
        end
    elseif typeof(value) == "table" then
        return `o:{str.encode(value, "json")}`
    else
        return nil
    end
end

local function deserialize(value: string): any
    if not value then
        return nil
    end

    local format, value = string.match(value, "^([snbo]):(.*)$")

    if format == "s" then
        return value
    elseif format == "n" then
        return tonumber(value)
    elseif format == "b" then
        return value == "1"
    elseif format == "o" then
        return str.decode(value, "json")
    else
        return nil
    end
end

local settings: number = sqlite.open(path.join(path.persist_dir("settings"), "settings.db"))

sqlite.batch(settings, [[
    CREATE TABLE IF NOT EXISTS settings (
        game  TEXT NOT NULL,
        key   TEXT NOT NULL,
        value TEXT NOT NULL,

        PRIMARY KEY (game, key)
    );

    PRAGMA optimize;
]])

local function get_raw_property(game: string, key: string): any
    local value: { string }? = sqlite.query_row(settings, "SELECT value FROM settings WHERE game = ?1 AND key = ?2", { game, key })

    if not value then
        return nil
    else
        return deserialize(value[1])
    end
end

local function set_raw_property(game: string, key: string, value: any)
    value = serialize(value)

    if not value then
        sqlite.execute(settings, "DELETE FROM settings WHERE game = ?1 AND key = ?2", { game, key })
    else
        sqlite.execute(settings, "INSERT OR REPLACE INTO settings (game, key, value) VALUES (?1, ?2, ?3)", { game, key, value })
    end
end

return function(options: BuilderOptions)
    local entries = {}

    for group_name, group in pairs(options.layout) do
        for entry_name, entry in pairs(group.entries) do
            local key = `{group_name}.{entry_name}`

            local entry_options = entry.options or {}

            entries[key] = {
                key = key,
                get = entry_options.get or nil,
                set = entry_options.set or nil,
                default = entry.entry.default
            }
        end
    end

    local function get_property(key: string): any
        local value = get_raw_property(options.game, key)

        if entries[key] then
            if entries[key].get then
                value = entries[key].get(value)
            end

            if entries[key].default ~= nil and value == nil then
                value = entries[key].default
            end
        end

        return value
    end

    local function set_property(key: string, value: any)
        if entries[key] then
            if entries[key].set then
                value = entries[key].set(value)
            end
        end

        set_raw_property(options.game, key, value)
    end

    return {
        get_property = get_property,
        set_property = set_property,

        get_layout = function(variant: GameVariant): { GroupLayout }
            local layout = {}

            for group_name, group in pairs(options.layout) do
                local group_layout: GroupLayout = {
                    title = group.title,
                    description = group.description,
                    entries = {}
                }

                for entry_name, entry in pairs(group.entries) do
                    local key = `{group_name}.{entry_name}`

                    local value = get_property(key)

                    entry.entry['value'] = value
                    entry.entry['selected'] = value

                    table.insert(group_layout.entries, {
                        name = key,
                        title = entry.title,
                        description = entry.description,
                        reactivity = entry.reactivity,
                        entry = entry.entry
                    } :: EntryLayout)
                end

                table.insert(layout, group_layout)
            end

            return layout
        end
    }
end
