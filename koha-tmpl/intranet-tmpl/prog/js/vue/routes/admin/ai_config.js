import { markRaw } from "vue";

import ResourceWrapper from "../../components/ResourceWrapper.vue";
import AIConfigShell from "../../components/Admin/AIConfig/AIConfigShell.vue";

import { $__ } from "@koha-vue/i18n";

export default {
    title: $__("Administration"),
    path: "",
    href: "/cgi-bin/koha/admin/admin-home.pl",
    is_base: true,
    is_default: true,
    children: [
        {
            title: $__("AI configuration"),
            path: "/cgi-bin/koha/admin/ai_config",
            component: markRaw(AIConfigShell),
            children: [
                {
                    path: "",
                    redirect: { name: "EmbeddingProvidersList" },
                },
                {
                    title: $__("Embedding providers"),
                    path: "embedding_providers",
                    is_end_node: true,
                    resource:
                        "Admin/EmbeddingProviders/EmbeddingProvidersResource.vue",
                    children: [
                        {
                            path: "",
                            name: "EmbeddingProvidersList",
                            component: markRaw(ResourceWrapper),
                        },
                        {
                            component: markRaw(ResourceWrapper),
                            name: "EmbeddingProvidersShow",
                            path: ":embedding_provider_id",
                            title: $__("Show embedding provider"),
                        },
                        {
                            component: markRaw(ResourceWrapper),
                            name: "EmbeddingProvidersFormAdd",
                            path: "add",
                            title: $__("Add embedding provider"),
                        },
                        {
                            component: markRaw(ResourceWrapper),
                            name: "EmbeddingProvidersFormAddEdit",
                            path: "edit/:embedding_provider_id",
                            title: $__("Edit embedding provider"),
                        },
                    ],
                },
                {
                    title: $__("LLM providers"),
                    path: "llm_providers",
                    is_end_node: true,
                    resource: "Admin/LLMProviders/LLMProvidersResource.vue",
                    children: [
                        {
                            path: "",
                            name: "LLMProvidersList",
                            component: markRaw(ResourceWrapper),
                        },
                        {
                            component: markRaw(ResourceWrapper),
                            name: "LLMProvidersShow",
                            path: ":llm_provider_id",
                            title: $__("Show LLM provider"),
                        },
                        {
                            component: markRaw(ResourceWrapper),
                            name: "LLMProvidersFormAdd",
                            path: "add",
                            title: $__("Add LLM provider"),
                        },
                        {
                            component: markRaw(ResourceWrapper),
                            name: "LLMProvidersFormAddEdit",
                            path: "edit/:llm_provider_id",
                            title: $__("Edit LLM provider"),
                        },
                    ],
                },
            ],
        },
    ],
};
