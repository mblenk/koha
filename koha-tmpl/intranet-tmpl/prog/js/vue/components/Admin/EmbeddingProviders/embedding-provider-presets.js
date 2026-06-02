export const EMBEDDING_PROVIDER_PRESETS = [
    {
        id: "openai",
        label: "OpenAI",
        url: "https://api.openai.com/v1/embeddings",
        request_body_template: '{"model":"{{model}}","input":"{{text}}"}',
        response_key: "data.0.embedding",
        auth_type: "bearer",
    },
    {
        id: "cohere",
        label: "Cohere",
        url: "https://api.cohere.ai/v1/embed",
        request_body_template:
            '{"model":"{{model}}","texts":["{{text}}"],"input_type":"search_document"}',
        response_key: "embeddings.0",
        auth_type: "bearer",
    },
    {
        id: "ollama",
        label: "Ollama",
        url: "http://localhost:11434/api/embed",
        request_body_template: '{"model":"{{model}}","input":"{{text}}"}',
        response_key: "embeddings.0",
        auth_type: "none",
    },
    {
        id: "huggingface",
        label: "HuggingFace Inference",
        url: "https://api-inference.huggingface.co/pipeline/feature-extraction/{{model}}",
        request_body_template: '{"inputs":"{{text}}"}',
        response_key: "0",
        auth_type: "bearer",
    },
    { id: "custom", label: "Custom" },
];

export default EMBEDDING_PROVIDER_PRESETS;
