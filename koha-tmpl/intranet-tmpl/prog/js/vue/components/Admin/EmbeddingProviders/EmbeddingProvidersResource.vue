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
                },
                {
                    name: "request_body_template",
                    required: true,
                    type: "textarea",
                    label: $__("Request body template"),
                    toolTip: $__(
                        'Full JSON body sent to the provider. Use "{{text}}" for the input and "{{model}}" for the model name. Examples — Ollama: {"model":"{{model}}","prompt":"{{text}}"} — OpenAI: {"model":"{{model}}","input":"{{text}}"} — Voyage (array): {"model":"{{model}}","input":["{{text}}"]}'
                    ),
                },
                {
                    name: "response_key",
                    required: true,
                    type: "text",
                    label: $__("Response embedding path"),
                    toolTip: $__(
                        "Dot-notation path to the embedding array in the response — e.g. 'embedding', 'data.0.embedding'"
                    ),
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
