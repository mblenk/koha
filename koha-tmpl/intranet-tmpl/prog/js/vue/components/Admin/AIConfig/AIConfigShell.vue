<template>
    <div>
        <ul class="nav nav-tabs" style="margin-bottom: 1em">
            <li class="nav-item">
                <router-link
                    class="nav-link"
                    active-class="active"
                    to="/cgi-bin/koha/admin/ai_config/embedding_providers"
                >
                    {{ $__("Embedding providers") }}
                </router-link>
            </li>
            <li class="nav-item">
                <router-link
                    class="nav-link"
                    active-class="active"
                    to="/cgi-bin/koha/admin/ai_config/llm_providers"
                >
                    {{ $__("LLM providers") }}
                </router-link>
            </li>
        </ul>
        <router-view />
    </div>
</template>

<script>
import { $__ } from "@koha-vue/i18n";

export default {
    name: "AIConfigShell",
    setup() {
        return {};
    },
};
</script>
