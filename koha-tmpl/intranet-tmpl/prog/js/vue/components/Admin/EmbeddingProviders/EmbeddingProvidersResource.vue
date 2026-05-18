<template>
    <BaseResource
        :routeAction="routeAction"
        :instancedResource="this"
    ></BaseResource>
</template>
<script>
import BaseResource from "../../BaseResource.vue";
import { useBaseResource } from "../../../composables/base-resource.js";
import { APIClient } from "../../../fetch/api-client.js";
import { $__ } from "@koha-vue/i18n";

export default {
    props: {
        routeAction: String,
    },
    setup(props) {
        const findEmbeddingPath = (obj, prefix = "") => {
            let bestMatch = { path: null, length: 0 };
            if (Array.isArray(obj)) {
                if (obj.every(v => typeof v === "number")) {
                    return { path: prefix, length: obj.length };
                }
                obj.forEach((item, i) => {
                    const child = findEmbeddingPath(
                        item,
                        prefix ? `${prefix}.${i}` : String(i)
                    );
                    if (child.length > bestMatch.length) bestMatch = child;
                });
            } else if (obj !== null && typeof obj === "object") {
                Object.keys(obj).forEach(key => {
                    const child = findEmbeddingPath(
                        obj[key],
                        prefix ? `${prefix}.${key}` : key
                    );
                    if (child.length > bestMatch.length) bestMatch = child;
                });
            }
            return bestMatch;
        };

        const baseResource = useBaseResource({
            resourceName: "embedding_provider",
            nameAttr: "name",
            idAttr: "embedding_provider_id",
            components: {
                show: "EmbeddingProvidersShow",
                list: "EmbeddingProvidersList",
                add: "EmbeddingProvidersFormAdd",
                edit: "EmbeddingProvidersFormAddEdit",
            },
            apiClient: APIClient.embedding_providers.embedding_providers,
            table: {
                resourceTableUrl:
                    APIClient.embedding_providers.httpClient._baseURL,
            },
            i18n: {
                deleteConfirmationMessage: $__(
                    "Are you sure you want to remove this embedding provider?"
                ),
                deleteSuccessMessage: $__("Embedding provider %s deleted"),
                displayName: $__("Embedding provider"),
                editLabel: $__("Edit embedding provider #%s"),
                emptyListMessage: $__(
                    "There are no embedding providers defined"
                ),
                newLabel: $__("New embedding provider"),
            },
            props,
            navigationOnFormSave: "EmbeddingProvidersList",
            resourceAttrs: [
                {
                    name: "embedding_provider_id",
                    required: true,
                    type: "text",
                    label: $__("ID"),
                    hideIn: ["Form"],
                },
                {
                    name: "name",
                    required: true,
                    type: "text",
                    label: $__("Name"),
                },
                {
                    name: "url",
                    required: true,
                    type: "text",
                    label: $__("URL"),
                },
                {
                    name: "model",
                    required: true,
                    type: "text",
                    label: $__("Model"),
                },
                {
                    name: "auth_type",
                    required: true,
                    type: "select",
                    label: $__("Authentication"),
                    selectLabel: "description",
                    requiredKey: "value",
                    options: [
                        {
                            value: "none",
                            description: $__("None"),
                        },
                        {
                            value: "bearer",
                            description: $__("Bearer token (API key)"),
                        },
                    ],
                },
                {
                    name: "api_key",
                    type: "text",
                    label: $__("API key"),
                    disabled: resource =>
                        resource.auth_type === "none" || !resource.auth_type,
                    hideIn: ["List"],
                    toolTip:
                        props.routeAction === "edit"
                            ? $__(
                                  "Leave blank to keep the existing API key. Enter a new value to replace it."
                              )
                            : null,
                },
                {
                    name: "request_body_template",
                    required: true,
                    type: "json",
                    label: $__("Request body template"),
                    toolTip: $__(
                        'Full JSON body sent to the provider. Use "{{text}}" for the input and "{{model}}" for the model name. Example: {"model":"{{model}}","prompt":"{{text}}"}'
                    ),
                },
                {
                    name: "response_payload",
                    type: "json",
                    label: $__("Example API response"),
                    hideIn: ["List", "Show"],
                    toolTip: $__(
                        "Paste a real or example JSON response from the provider. The embedding path will be detected automatically and populated in the field below."
                    ),
                    onChange: resource => {
                        if (!resource.response_payload) return;
                        try {
                            const result = findEmbeddingPath(
                                JSON.parse(resource.response_payload)
                            );
                            if (result.path)
                                resource.response_key = result.path;
                        } catch (e) {
                            // Invalid JSON — the CodeMirror linter shows the error inline
                        }
                    },
                },
                {
                    name: "response_key",
                    required: true,
                    type: "text",
                    label: $__("Response embedding path"),
                    toolTip: $__(
                        "Dot-notation path to the embedding array in the response — e.g. 'embedding', 'data.0.embedding'"
                    ),
                    disabled: resource => !!resource.response_payload,
                },
                {
                    name: "dimensions",
                    required: true,
                    type: "number",
                    label: $__("Vector dimensions"),
                },
                {
                    name: "status",
                    required: true,
                    type: "select",
                    label: $__("Status"),
                    options: [
                        {
                            value: "active",
                            description: $__("Active"),
                        },
                        {
                            value: "inactive",
                            description: $__("Inactive"),
                        },
                    ],
                    selectLabel: "description",
                    requiredKey: "value",
                },
            ],
        });

        const tableOptions = {
            options: {},
            url: baseResource.getResourceTableUrl(),
            actions: {
                "-1": ["edit", "delete"],
            },
        };

        const onFormSave = (e, embeddingProviderToSave) => {
            e.preventDefault();
            const embeddingProvider = JSON.parse(
                JSON.stringify(embeddingProviderToSave)
            );
            const embeddingProviderId = embeddingProvider.embedding_provider_id;

            delete embeddingProvider.embedding_provider_id;
            delete embeddingProvider.response_payload;

            if (embeddingProviderId) {
                return baseResource.apiClient
                    .update(embeddingProvider, embeddingProviderId)
                    .then(
                        () => {
                            baseResource.setMessage(
                                $__("Embedding provider updated!")
                            );
                        },
                        error => {}
                    );
            } else {
                return baseResource.apiClient.create(embeddingProvider).then(
                    () => {
                        baseResource.setMessage(
                            $__("Embedding provider created!")
                        );
                    },
                    error => {}
                );
            }
        };

        return {
            ...baseResource,
            tableOptions,
            onFormSave,
        };
    },
    name: "EmbeddingProvidersResource",
    emits: ["select-resource"],
    components: {
        BaseResource,
    },
};
</script>
