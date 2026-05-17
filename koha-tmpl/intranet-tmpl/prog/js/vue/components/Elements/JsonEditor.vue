<template>
    <div class="json-editor-field">
        <textarea ref="editorEl" :id="id" />
    </div>
</template>

<script>
import { ref, watch, onMounted, onBeforeUnmount } from "vue";

export default {
    name: "JsonEditor",
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
                mode: "application/json",
                lineNumbers: true,
                lineWrapping: true,
                viewportMargin: Infinity,
                indentWithTabs: false,
                tabSize: 2,
                readOnly: props.disabled || false,
                lint: {
                    getAnnotations: text => {
                        const errors = [];
                        if (!text) return errors;
                        try {
                            JSON.parse(text);
                        } catch (e) {
                            const match = e.message.match(/position (\d+)/i);
                            const pos = match ? parseInt(match[1]) : 0;
                            const lines = text.slice(0, pos).split("\n");
                            const line = lines.length - 1;
                            const ch = lines[lines.length - 1].length;
                            errors.push({
                                from: window.CodeMirror.Pos(line, ch),
                                to: window.CodeMirror.Pos(line, ch + 1),
                                message: e.message,
                                severity: "error",
                            });
                        }
                        return errors;
                    },
                },
                gutters: ["CodeMirror-lint-markers"],
            });
            if (props.modelValue) editor.setValue(props.modelValue);
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
.json-editor-field {
    display: inline-block;
    vertical-align: top;
    max-width: 100%;
    min-width: 30%;
}

.json-editor-field .CodeMirror {
    height: auto;
    min-height: 80px;
    border: 1px solid #ccced1;
    border-radius: 4px;
    font-size: 13px;
}

.json-editor-field .CodeMirror-scroll {
    overflow: visible !important;
    position: static;
}
</style>
