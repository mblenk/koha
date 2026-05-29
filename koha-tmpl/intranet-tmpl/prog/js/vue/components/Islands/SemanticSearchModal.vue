<template>
    <div
        id="semanticSearchModal"
        class="modal fade"
        tabindex="-1"
        aria-labelledby="semanticSearchModalLabel"
        aria-hidden="true"
    >
        <div :class="['modal-dialog', isLlmAvailable ? 'modal-xl' : '']">
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
                                <a
                                    :href="biblioUrl(r.biblio_id)"
                                    target="_blank"
                                    rel="noopener noreferrer"
                                >
                                    <strong>{{
                                        r.title || $__("(no title)")
                                    }}</strong>
                                </a>
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
import { ref, computed, nextTick, onMounted, watch } from "vue";
import { $__ } from "@koha-vue/i18n";
import { APIClient } from "../../fetch/api-client.js";

export default {
    name: "SemanticSearchModal",
    props: {
        searchUrl: { type: String, required: true },
        llmAvailable: { type: String, default: "0" },
        borrowerNumber: { type: String, default: "" },
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

        const storageKey = computed(() =>
            props.borrowerNumber
                ? `koha_search_chat_${props.borrowerNumber}`
                : null
        );

        const loadFromStorage = () => {
            if (!storageKey.value) return;
            try {
                const stored = localStorage.getItem(storageKey.value);
                if (stored) {
                    const { conversation: c, results: r } = JSON.parse(stored);
                    conversation.value = c || [];
                    results.value = r || [];
                }
            } catch (_) {}
        };

        const saveToStorage = () => {
            if (!storageKey.value) return;
            try {
                localStorage.setItem(
                    storageKey.value,
                    JSON.stringify({
                        conversation: conversation.value,
                        results: results.value,
                    })
                );
            } catch (_) {}
        };

        watch(conversation, saveToStorage, { deep: true });
        watch(results, saveToStorage, { deep: true });

        onMounted(() => {
            loadFromStorage();

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
                errorMsg.value = "";
            });

            document.querySelectorAll("#logout, .logout").forEach(el => {
                el.addEventListener("click", () => {
                    if (storageKey.value) {
                        localStorage.removeItem(storageKey.value);
                    }
                });
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

            const historyPayload = conversation.value.map(
                ({ role, content }) => ({ role, content })
            );

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
                    historyPayload,
                    searchLocation
                );
                conversation.value = [
                    ...conversation.value,
                    {
                        role: "assistant",
                        content: data.reply,
                        search_url: data.search_url || null,
                    },
                ];
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

        const isOpac = computed(() => props.searchUrl.includes("opac"));

        const biblioUrl = biblioId => {
            if (isOpac.value) {
                return `/cgi-bin/koha/opac-detail.pl?biblionumber=${biblioId}`;
            }
            return `/cgi-bin/koha/catalogue/detail.pl?biblionumber=${biblioId}`;
        };

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
            biblioUrl,
        };
    },
};
</script>
