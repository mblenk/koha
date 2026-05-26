<template>
    <BaseResource
        v-if="initialized"
        :routeAction="routeAction"
        :instancedResource="this"
    ></BaseResource>
</template>
<script>
import BaseResource from "../../BaseResource.vue";
import { useBaseResource } from "../../../composables/base-resource.js";
import { APIClient } from "../../../fetch/api-client.js";
import { $__ } from "@koha-vue/i18n";
import { EMBEDDING_PROVIDER_PRESETS } from "./embedding-provider-presets.js";
import { onBeforeMount, ref } from "vue";

export default {
    props: {
        routeAction: String,
    },
    setup(props) {
        const initialized = ref(false);
        let esVersion = null;
        onBeforeMount(async () => {
            APIClient.search.embedding_config.get().then(result => {
                esVersion = result.elasticsearch_version;
                if (esVersion !== null && esVersion < 8) {
                    baseResource.setMessage(
                        $__(
                            "Elasticsearch version %s detected. Version 8 or higher is required for semantic search."
                        ).format(esVersion || "unknown")
                    );
                }
                initialized.value = true;
            });
        });

        const defaultToolbarButtons = (defaultButtons, resource) => {
            return {
                list: defaultButtons.list.filter(
                    button => esVersion && esVersion >= 8
                ),
                show: defaultButtons.show,
            };
        };

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
            apiClient: APIClient.search.embedding_providers,
            table: {
                resourceTableUrl: "/api/v1/embedding_providers",
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
            defaultToolbarButtons,
            resourceAttrs: [
                {
                    name: "embedding_provider_id",
                    required: true,
                    type: "text",
                    label: $__("ID"),
                    hideIn: ["Form", "Show"],
                },
                {
                    name: "preset",
                    type: "select",
                    label: $__("Provider preset"),
                    selectLabel: "label",
                    requiredKey: "id",
                    options: EMBEDDING_PROVIDER_PRESETS,
                    hideIn: ["List", "Show"],
                    toolTip: $__(
                        "Select a provider to pre-fill the configuration fields below."
                    ),
                    onSelected: resource => {
                        const preset = EMBEDDING_PROVIDER_PRESETS.find(
                            p => p.id === resource.preset
                        );
                        if (!preset || preset.id === "custom") return;
                        resource.url = preset.url;
                        resource.request_body_template =
                            preset.request_body_template;
                        resource.response_key = preset.response_key;
                        resource.auth_type = preset.auth_type;
                        if (preset.suggested_model)
                            resource.model = preset.suggested_model;
                    },
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
                    disabled: resource =>
                        !!(resource.preset && resource.preset !== "custom"),
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
                    format: (value, resource, attr) => {
                        return attr.options.find(op => op.value === value)
                            .description;
                    },
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
                        'Full JSON body sent to the provider. Use "{{text}}" for the input and "{{model}}" for the model name. Example: {"model":"{{model}}","prompt":"{{text}}"}'
                    ),
                    disabled: resource =>
                        !!(resource.preset && resource.preset !== "custom"),
                    hideIn: ["List", "Show"],
                },
                {
                    name: "query_body_template",
                    type: "json",
                    label: $__("Query body template"),
                    toolTip: $__(
                        'Optional: JSON body template used when embedding search queries. Leave blank to use the request body template. Use this for asymmetric models that require different prefixes for documents and queries — e.g. {"model":"{{model}}","prompt":"search_query: {{text}}"}'
                    ),
                    disabled: resource =>
                        !!(resource.preset && resource.preset !== "custom"),
                    hideIn: ["List", "Show"],
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
                    hideIn: ["List", "Show"],
                },
                {
                    name: "response_key",
                    required: true,
                    type: "text",
                    label: $__("Response embedding path"),
                    toolTip: $__(
                        "Dot-notation path to the embedding array in the response — e.g. 'embedding', 'data.0.embedding'"
                    ),
                    disabled: resource =>
                        !!resource.response_payload ||
                        !!(resource.preset && resource.preset !== "custom"),
                    hideIn: ["List", "Show"],
                },
                {
                    name: "marc_fields_config",
                    type: "yaml",
                    label: $__("Index fields"),
                    toolTip: $__(
                        "YAML defining which biblio and MARC fields should be used for matching search queries. Set include_authorities: true on a MARC field spec to append USE-FOR variant forms (4XX) and scope notes (680) from linked authority records."
                    ),
                    defaultValue: [
                        "biblio_fields:",
                        "  - title",
                        "  - subtitle",
                        "  - author",
                        "marc_fields:",
                        '  - tag: "6.."',
                        '    subfield: "a"',
                        "    include_authorities: true",
                        '  - tag: "520"',
                        '    subfield: "a"',
                    ].join("\n"),
                    hideIn: ["List"],
                },
                {
                    name: "dimensions",
                    required: true,
                    type: "number",
                    label: $__("Vector dimensions"),
                    hideIn: ["List"],
                    disabled: resource => !!resource.embedding_provider_id,
                },
                {
                    name: "batch_size",
                    type: "number",
                    label: $__("Batch size"),
                    toolTip: $__(
                        "Number of texts sent per API call. Check that your provider supports batch requests, if not then leave this field blank."
                    ),
                    hideIn: ["List"],
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
                    format: (value, resource, attr) => {
                        return attr.options.find(op => op.value === value)
                            .description;
                    },
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

        let isProviderActive = false;
        const afterResourceFetch = (componentData, resource, caller) => {
            if (caller === "form") {
                isProviderActive = resource.status === "active" ? true : false;
            }
        };

        const performSave = (provider, providerId) => {
            if (providerId) {
                return baseResource.apiClient
                    .update(provider, providerId)
                    .then(provider => {
                        baseResource.setMessage(
                            $__("Embedding provider updated!")
                        );
                        return provider;
                    });
            }
            return baseResource.apiClient.create(provider).then(provider => {
                baseResource.setMessage($__("Embedding provider created!"));
                return provider;
            });
        };

        const onFormSave = (e, embeddingProviderToSave) => {
            e.preventDefault();
            const embeddingProvider = JSON.parse(
                JSON.stringify(embeddingProviderToSave)
            );
            const embeddingProviderId = embeddingProvider.embedding_provider_id;

            delete embeddingProvider.embedding_provider_id;
            delete embeddingProvider.response_payload;
            delete embeddingProvider.preset;

            if (
                embeddingProvider.status === "active" &&
                esVersion !== null &&
                esVersion < 8
            ) {
                baseResource.setMessage(
                    $__(
                        "Cannot activate: Elasticsearch version %s detected. Version 8 or higher is required."
                    ).format(esVersion)
                );
                return Promise.resolve();
            }

            if (embeddingProvider.status === "active" && !isProviderActive) {
                return new Promise(resolve => {
                    baseResource.setConfirmationDialog(
                        {
                            title: $__(
                                "Semantic search will be temporarily unavailable"
                            ),
                            message: $__(
                                "Saving this provider as active will trigger a full catalogue re-index. Semantic search will be disabled until the re-index is complete. Do you want to proceed?"
                            ),
                            accept_label: $__("Yes, save and re-index"),
                            cancel_label: $__("No (save provider as inactive)"),
                            cancel_callback: () => {
                                embeddingProvider.status = "inactive";
                                performSave(
                                    embeddingProvider,
                                    embeddingProviderId
                                ).then(resolve);
                            },
                        },
                        async () => {
                            const provider = await performSave(
                                embeddingProvider,
                                embeddingProviderId
                            );
                            resolve(provider);
                        }
                    );
                });
            } else {
                return performSave(embeddingProvider, embeddingProviderId);
            }
        };

        return {
            ...baseResource,
            tableOptions,
            onFormSave,
            afterResourceFetch,
            initialized,
        };
    },
    name: "EmbeddingProvidersResource",
    emits: ["select-resource"],
    components: {
        BaseResource,
    },
};
</script>
