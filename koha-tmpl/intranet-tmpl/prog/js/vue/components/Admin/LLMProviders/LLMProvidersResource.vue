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
            resourceName: "llm_provider",
            nameAttr: "name",
            idAttr: "llm_provider_id",
            components: {
                show: "LLMProvidersShow",
                list: "LLMProvidersList",
                add: "LLMProvidersFormAdd",
                edit: "LLMProvidersFormAddEdit",
            },
            apiClient: APIClient.llm_providers.llm_providers,
            table: {
                resourceTableUrl: APIClient.llm_providers.httpClient._baseURL,
            },
            i18n: {
                deleteConfirmationMessage: $__(
                    "Are you sure you want to remove this LLM provider?"
                ),
                deleteSuccessMessage: $__("LLM provider %s deleted"),
                displayName: $__("LLM provider"),
                editLabel: $__("Edit LLM provider #%s"),
                emptyListMessage: $__("There are no LLM providers defined"),
                newLabel: $__("New LLM provider"),
            },
            props,
            resourceAttrs: [
                {
                    name: "llm_provider_id",
                    required: true,
                    type: "text",
                    label: $__("ID"),
                    hideIn: ["Form", "Show"],
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
                    toolTip: $__(
                        "Full endpoint URL for the chat completions API"
                    ),
                },
                {
                    name: "model",
                    required: true,
                    type: "text",
                    label: $__("Model"),
                    toolTip: $__(
                        'Model identifier substituted as "{{model}}" in the request body template — e.g. gpt-4o, claude-3-5-sonnet-20241022, llama3'
                    ),
                },
                {
                    name: "auth_type",
                    required: true,
                    type: "select",
                    label: $__("Authentication"),
                    selectLabel: "description",
                    requiredKey: "value",
                    options: [
                        { value: "none", description: $__("None") },
                        {
                            value: "bearer",
                            description: $__("Bearer token (API key)"),
                        },
                    ],
                    format: (value, resource, attr) =>
                        attr.options.find(op => op.value === value).description,
                },
                {
                    name: "api_key",
                    type: "text",
                    label: $__("API key"),
                    disabled: resource =>
                        resource.auth_type === "none" || !resource.auth_type,
                    hideIn: ["List", "Show"],
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
                        'Full JSON body sent to the provider. Use "{{model}}" for the model name, "{{messages}}" for the conversation array, and "{{system_prompt}}" for the system prompt. Example: {"model":"{{model}}","messages":{{messages}}}'
                    ),
                    hideIn: ["List", "Show"],
                },
                {
                    name: "response_key",
                    required: true,
                    type: "text",
                    label: $__("Response text path"),
                    toolTip: $__(
                        "Dot-notation path to the reply text in the response — e.g. choices.0.message.content"
                    ),
                    hideIn: ["List", "Show"],
                },
                {
                    name: "system_prompt",
                    type: "text",
                    label: $__("System prompt"),
                    toolTip: $__(
                        "Optional: override the default library search assistant prompt injected at the start of every conversation."
                    ),
                    hideIn: ["List"],
                },
                {
                    name: "status",
                    required: true,
                    type: "select",
                    label: $__("Status"),
                    options: [
                        { value: "active", description: $__("Active") },
                        { value: "inactive", description: $__("Inactive") },
                    ],
                    selectLabel: "description",
                    requiredKey: "value",
                    format: (value, resource, attr) =>
                        attr.options.find(op => op.value === value).description,
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

        const onFormSave = (e, llmProviderToSave) => {
            e.preventDefault();
            const provider = JSON.parse(JSON.stringify(llmProviderToSave));
            const providerId = provider.llm_provider_id;
            delete provider.llm_provider_id;

            if (providerId) {
                return baseResource.apiClient
                    .update(provider, providerId)
                    .then(() => {
                        baseResource.setMessage($__("LLM provider updated!"));
                    });
            }
            return baseResource.apiClient.create(provider).then(() => {
                baseResource.setMessage($__("LLM provider created!"));
            });
        };

        return {
            ...baseResource,
            tableOptions,
            onFormSave,
        };
    },
    name: "LLMProvidersResource",
    emits: ["select-resource"],
    components: {
        BaseResource,
    },
};
</script>
