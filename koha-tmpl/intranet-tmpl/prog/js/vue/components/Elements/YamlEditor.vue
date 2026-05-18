<template>
    <div class="yaml-editor-field">
        <textarea ref="editorEl" :id="id" />
    </div>
</template>

<script>
import { ref, watch, onMounted, onBeforeUnmount } from "vue";

export default {
    name: "YamlEditor",
    props: {
        modelValue: String,
        disabled: Boolean,
        id: String,
        required: Boolean,
    },
    emits: ["update:modelValue"],
    setup(props, { emit }) {
        const editorEl = ref(null);
        let editor = null;

        onMounted(() => {
            editor = window.CodeMirror.fromTextArea(editorEl.value, {
                mode: "text/x-yaml",
                lineNumbers: true,
                lineWrapping: true,
                viewportMargin: Infinity,
                indentWithTabs: false,
                tabSize: 2,
                readOnly: props.disabled || false,
                lint: true,
                gutters: ["CodeMirror-lint-markers"],
            });
            const initialValue = props.modelValue || "";
            editor.setValue(initialValue);
            if (!props.modelValue && initialValue) {
                emit("update:modelValue", initialValue);
            }
            editor.on("change", () =>
                emit("update:modelValue", editor.getValue())
            );
        });

        onBeforeUnmount(() => {
            if (editor) editor.toTextArea();
        });

        watch(
            () => props.modelValue,
            value => {
                if (editor && editor.getValue() !== value)
                    editor.setValue(value || "");
            }
        );

        return { editorEl };
    },
};
</script>

<style>
.yaml-editor-field {
    display: inline-block;
    vertical-align: top;
    max-width: 100%;
    min-width: 30%;
}

.yaml-editor-field .CodeMirror {
    height: auto;
    min-height: 80px;
    border: 1px solid #ccced1;
    border-radius: 4px;
    font-size: 13px;
}

.yaml-editor-field .CodeMirror-scroll {
    overflow: visible !important;
    position: static;
}
</style>
