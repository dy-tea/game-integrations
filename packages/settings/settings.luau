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

local settings: number = sqlite.open(path.join(path.persist_dir("settings"), "settings.db"))

sqlite.batch(settings, [[
    CREATE TABLE IF NOT EXISTS settings (
        game_name    TEXT NOT NULL,
        group_name   TEXT NOT NULL,
        entry_name   TEXT NOT NULL,
        value        TEXT,

        PRIMARY KEY (game_name, group_name, entry_name)
    );

    PRAGMA optimize;
]])

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

type EntryInfo = {
    key: string,
    game_name: string,
    group_name: string,
    entry_name: string,
    options: BuilderEntryOptions,
    default: any
}

local function get_property(entry: EntryInfo): any
    local value: { string }? = sqlite.query_row(
        settings,
        "SELECT value FROM settings WHERE game_name = ?1 AND group_name = ?2 AND entry_name = ?3",
        { entry.game_name, entry.group_name, entry.entry_name }
    )

    if not value then
        return entry.default
    elseif entry.options.get then
        return entry.options.get(deserialize(value[1])) or entry.default
    else
        return deserialize(value[1])
    end
end

local function set_property(entry: EntryInfo, value: any)
    if entry.options.set then
        value = serialize(entry.options.set(value))
    else
        value = serialize(value)
    end

    if not value then
        sqlite.execute(
            settings,
            "DELETE FROM settings WHERE game_name = ?1 AND group_name = ?2 AND entry_name = ?3",
            { entry.game_name, entry.group_name, entry.entry_name }
        )
    else
        sqlite.execute(
            settings,
            "INSERT OR REPLACE INTO settings (game_name, group_name, entry_name, value) VALUES (?1, ?2, ?3, ?4)",
            { entry.game_name, entry.group_name, entry.entry_name, value }
        )
    end
end

return function(options: BuilderOptions)
    local entries: { [string]: EntryInfo } = {}

    for group_name, group in pairs(options.layout) do
        for entry_name, entry in pairs(group.entries) do
            local key = `{group_name}.{entry_name}`

            entries[key] = {
                key = key,
                game_name = options.game,
                group_name = group_name,
                entry_name = entry_name,
                options = entry.options or {},
                default = entry.entry.default
            }
        end
    end

    return {
        get_property = function(key: string) return get_property(entries[key]) end,
        set_property = function(key: string, value: any) set_property(entries[key], value) end,

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

                    local value = get_property(entries[key]) or entry.entry.default

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
