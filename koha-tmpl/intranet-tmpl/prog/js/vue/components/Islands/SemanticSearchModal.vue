<template>
    <div
        id="semanticSearchModal"
        class="modal fade"
        tabindex="-1"
        aria-labelledby="semanticSearchModalLabel"
        aria-hidden="true"
    >
        <div :class="['modal-dialog', isLlmAvailable ? 'modal-lg' : '']">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 id="semanticSearchModalLabel" class="modal-title">
                        {{
                            isLlmAvailable
                                ? $__("Search assistant")
                                : $__("Semantic search")
                        }}
                    </h5>
                    <button
                        type="button"
                        class="btn-close"
                        data-bs-dismiss="modal"
                        :aria-label="$__('Close')"
                    ></button>
                </div>

                <!-- LLM chat mode -->
                <template v-if="isLlmAvailable">
                    <div
                        ref="chatBody"
                        class="modal-body"
                        style="max-height: 420px; overflow-y: auto"
                    >
                        <div v-if="isFirstMessage" class="text-muted">
                            <p>
                                {{
                                    $__(
                                        "Ask me what you're looking for in the library catalog."
                                    )
                                }}
                            </p>
                        </div>
                        <div
                            v-for="(turn, i) in conversation"
                            :key="i"
                            :class="[
                                'd-flex',
                                'mb-2',
                                turn.role === 'user'
                                    ? 'justify-content-end'
                                    : 'justify-content-start',
                            ]"
                        >
                            <div
                                :class="[
                                    'px-3',
                                    'py-2',
                                    'rounded',
                                    turn.role === 'user'
                                        ? 'bg-primary text-white'
                                        : 'bg-light border',
                                ]"
                                style="max-width: 85%; white-space: pre-wrap"
                            >
                                {{ turn.content }}
                                <div v-if="turn.search_url" class="mt-2">
                                    <a
                                        :href="turn.search_url"
                                        class="btn btn-sm btn-outline-primary"
                                    >
                                        {{ $__("See all results") }}
                                    </a>
                                </div>
                            </div>
                        </div>
                        <ul
                            v-if="results.length"
                            class="list-group list-group-flush mt-2"
                        >
                            <li
                                v-for="r in results"
                                :key="r.biblio_id"
                                class="list-group-item px-0"
                            >
                                <strong>{{
                                    r.title || $__("(no title)")
                                }}</strong>
                                <span v-if="r.author">
                                    &mdash; {{ r.author }}</span
                                >
                                <span
                                    v-if="r.publication_year"
                                    class="text-muted"
                                >
                                    ({{ r.publication_year }})
                                </span>
                            </li>
                        </ul>
                        <div v-if="loading" class="text-muted mt-2">
                            <em>{{ $__("Searching…") }}</em>
                        </div>
                        <div
                            v-if="errorMsg"
                            class="alert alert-danger mt-2"
                            role="alert"
                        >
                            {{ errorMsg }}
                        </div>
                    </div>
                    <div
                        class="modal-footer flex-column align-items-stretch gap-2"
                    >
                        <div class="d-flex gap-2">
                            <input
                                ref="chatInput"
                                v-model="query"
                                type="text"
                                class="form-control"
                                :placeholder="
                                    isFirstMessage
                                        ? $__('Type your query')
                                        : $__('Type your follow-up…')
                                "
                                :disabled="loading"
                                @keyup.enter="sendMessage"
                            />
                            <button
                                class="btn btn-primary"
                                :disabled="loading || !query.trim()"
                                @click="sendMessage"
                            >
                                {{ $__("Send") }}
                            </button>
                        </div>
                        <div class="d-flex justify-content-between">
                            <button
                                type="button"
                                class="btn btn-secondary"
                                data-bs-dismiss="modal"
                            >
                                {{ $__("Close") }}
                            </button>
                        </div>
                    </div>
                </template>

                <!-- Simple redirect mode -->
                <template v-else>
                    <div class="modal-body">
                        <label for="semanticSearchQuery" class="form-label">
                            {{
                                $__(
                                    "Describe what you're looking for in plain language"
                                )
                            }}
                        </label>
                        <textarea
                            id="semanticSearchQuery"
                            v-model="query"
                            class="form-control"
                            rows="3"
                            style="margin-top: 1em"
                            @keyup.enter="submit"
                        ></textarea>
                    </div>
                    <div class="modal-footer">
                        <button
                            type="button"
                            class="btn btn-secondary"
                            data-bs-dismiss="modal"
                        >
                            {{ $__("Cancel") }}
                        </button>
                        <button
                            type="button"
                            class="btn btn-primary"
                            @click="submit"
                        >
                            {{ $__("Search") }}
                        </button>
                    </div>
                </template>
            </div>
        </div>
    </div>
</template>

<script>
import { ref, computed, nextTick, onMounted } from "vue";
import { $__ } from "@koha-vue/i18n";
import { APIClient } from "../../fetch/api-client.js";

export default {
    name: "SemanticSearchModal",
    props: {
        searchUrl: { type: String, required: true },
        llmAvailable: { type: String, default: "0" },
    },
    setup(props) {
        const isLlmAvailable = computed(
            () => props.llmAvailable === "1" || props.llmAvailable === "true"
        );

        const query = ref("");
        const conversation = ref([]);
        const results = ref([]);
        const loading = ref(false);
        const errorMsg = ref("");
        const chatBody = ref(null);
        const chatInput = ref(null);

        onMounted(() => {
            const modalEl = document.getElementById("semanticSearchModal");
            if (!modalEl) return;
            modalEl.addEventListener("shown.bs.modal", () => {
                if (isLlmAvailable.value) {
                    chatInput.value?.focus();
                } else {
                    document.getElementById("semanticSearchQuery")?.focus();
                }
            });
            modalEl.addEventListener("hidden.bs.modal", () => {
                query.value = "";
                if (isLlmAvailable.value) {
                    conversation.value = [];
                    results.value = [];
                    errorMsg.value = "";
                }
            });
        });

        const scrollToBottom = async () => {
            await nextTick();
            if (chatBody.value) {
                chatBody.value.scrollTop = chatBody.value.scrollHeight;
            }
        };

        const sendMessage = async () => {
            const messageQuery = query.value.trim();
            if (!messageQuery || loading.value) return;

            loading.value = true;
            errorMsg.value = "";
            results.value = [];
            query.value = "";

            conversation.value = [
                ...conversation.value,
                { role: "user", content: messageQuery },
            ];
            await scrollToBottom();

            const searchLocation = props.searchUrl.includes("opac")
                ? "opac"
                : "intranet";

            try {
                const data = await APIClient.search.search_agent.converse(
                    messageQuery,
                    conversation.value.map(({ role, content }) => ({
                        role,
                        content,
                    })),
                    searchLocation
                );
                const updatedConversation = data.conversation || [];

                const savedUrls = new Map(
                    conversation.value
                        .map((m, i) => [i, m.search_url])
                        .filter(([, url]) => url)
                );
                savedUrls.forEach((url, i) => {
                    if (updatedConversation[i]?.role === "assistant") {
                        updatedConversation[i].search_url = url;
                    }
                });

                if (data.search_url && updatedConversation.length) {
                    const last =
                        updatedConversation[updatedConversation.length - 1];
                    if (last.role === "assistant")
                        last.search_url = data.search_url;
                }
                conversation.value = updatedConversation;
                results.value = data.results || [];
            } catch (e) {
                errorMsg.value = $__(
                    "Sorry, something went wrong. Please try again."
                );
            } finally {
                loading.value = false;
                await scrollToBottom();
            }
        };

        const submit = () => {
            const q = query.value.trim();
            if (!q) return;
            window.location.href =
                props.searchUrl + "?q=" + encodeURIComponent(q) + "&semantic=1";
        };

        const isFirstMessage = computed(() => {
            return !conversation.value.length && !loading.value;
        });

        return {
            isLlmAvailable,
            query,
            conversation,
            results,
            loading,
            errorMsg,
            chatBody,
            chatInput,
            sendMessage,
            submit,
            isFirstMessage,
        };
    },
};
</script>
