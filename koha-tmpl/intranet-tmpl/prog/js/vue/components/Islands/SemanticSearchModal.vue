<template>
    <div
        id="semanticSearchModal"
        class="modal fade"
        tabindex="-1"
        aria-labelledby="semanticSearchModalLabel"
        aria-hidden="true"
    >
        <div class="modal-dialog">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 id="semanticSearchModalLabel" class="modal-title">
                        {{ $__("Semantic search") }}
                    </h5>
                    <button
                        type="button"
                        class="btn-close"
                        data-bs-dismiss="modal"
                        :aria-label="$__('Close')"
                    ></button>
                </div>
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
                        @keyup.enter="submit"
                        style="margin-top: 1em"
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
            </div>
        </div>
    </div>
</template>

<script>
import { ref, onMounted } from "vue";
import { $__ } from "@koha-vue/i18n";

export default {
    name: "SemanticSearchModal",
    props: {
        searchUrl: { type: String, required: true },
    },
    setup(props) {
        const query = ref("");

        onMounted(() => {
            const modalEl = document.getElementById("semanticSearchModal");
            if (modalEl) {
                modalEl.addEventListener("shown.bs.modal", () => {
                    document.getElementById("semanticSearchQuery")?.focus();
                });
                modalEl.addEventListener("hidden.bs.modal", () => {
                    query.value = "";
                });
            }
        });

        const submit = () => {
            const q = query.value.trim();
            if (!q) return;
            window.location.href =
                props.searchUrl + "?q=" + encodeURIComponent(q) + "&semantic=1";
        };

        return { query, submit };
    },
};
</script>
