import { markRaw } from "vue";

import ResourceWrapper from "../../components/ResourceWrapper.vue";

import { $__ } from "@koha-vue/i18n";

export default {
    title: $__("Administration"),
    path: "",
    href: "/cgi-bin/koha/admin/admin-home.pl",
    is_base: true,
    is_default: true,
    children: [
        {
            title: $__("Embedding providers"),
            path: "/cgi-bin/koha/admin/embedding_providers",
            is_end_node: true,
            resource: "Admin/EmbeddingProviders/EmbeddingProvidersResource.vue",
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
    ],
};
