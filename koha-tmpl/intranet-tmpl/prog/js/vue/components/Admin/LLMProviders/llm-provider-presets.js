export const LLM_PROVIDER_PRESETS = [
    {
        id: "openai",
        label: "OpenAI",
        url: "https://api.openai.com/v1/chat/completions",
        request_body_template:
            '{"model":"{{model}}","messages":"{{messages}}"}',
        response_key: "choices.0.message.content",
        suggested_model: "gpt-4o",
        auth_type: "bearer",
    },
    {
        id: "anthropic",
        label: "Anthropic",
        url: "https://api.anthropic.com/v1/messages",
        request_body_template:
            '{"model":"{{model}}","max_tokens":1024,"system":"{{system_prompt}}","messages":"{{messages}}"}',
        response_key: "content.0.text",
        suggested_model: "claude-3-5-sonnet-20241022",
        auth_type: "bearer",
    },
    {
        id: "ollama",
        label: "Ollama",
        url: "http://localhost:11434/api/chat",
        request_body_template:
            '{"model":"{{model}}","messages":"{{messages}}","stream":false}',
        response_key: "message.content",
        suggested_model: "llama3",
        auth_type: "none",
    },
    { id: "custom", label: "Custom" },
];

export default LLM_PROVIDER_PRESETS;
