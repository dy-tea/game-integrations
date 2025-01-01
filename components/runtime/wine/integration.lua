return {
    standard = 1,

    groups = function(source_platform: string, target_platform: string)
        return {
            {
                name = "wine-staging-tkg",
                title = "Wine Staging TKG"
            }
        }
    end,

    components = function(group: string)
        return {
            {
                name = "wine-staging-tkg-9.22",
                title = "Wine Staging TKG 9.22"
            },
            {
                name = "wine-staging-tkg-9.21",
                title = "Wine Staging TKG 9.21"
            },
            {
                name = "wine-staging-tkg-9.20",
                title = "Wine Staging TKG 9.20"
            }
        }
    end,

    component = {
        get_status = function(component: string)
            return nil
        end,

        get_diff = function(component: string)
            return nil
        end,

        apply = function(component: string, launch_info: table)
            return nil
        end
    }
}
