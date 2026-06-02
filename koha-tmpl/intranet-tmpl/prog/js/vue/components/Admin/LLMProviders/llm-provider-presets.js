export const LLM_PROVIDER_PRESETS = [
    {
        id: "openai",
        label: "OpenAI",
        url: "https://api.openai.com/v1/chat/completions",
        request_body_template:
            '{"model":"{{model}}","messages":"{{messages}}","tools":"{{tool_definitions}}"}',
        response_key: "choices.0.message.content",
        auth_type: "bearer",
        tool_definitions:
            '[{"type":"function","function":{"name":"search_catalogue","description":"Search the library catalogue for books and materials. Always call this before responding to the user.","parameters":{"type":"object","properties":{"query":{"type":"string","description":"Primary search phrase — used as fallback for both searches when semantic_query or keyword_query are not provided."},"semantic_query":{"type":"string","description":"Optimised for vector/semantic search. A descriptive phrase (2-5 words) capturing the topic and context (e.g. \\"Tudor dynasty English monarchy\\")."},"keyword_query":{"type":"string","description":"Optimised for keyword search. The single most distinctive word or at most two words — shorter is better because keyword search requires ALL words to appear in a record (e.g. \\"Tudor\\" not \\"Tudor dynasty\\")."},"strategy":{"type":"string","enum":["semantic","keyword","hybrid"],"description":"hybrid: use for most searches; provide semantic_query and keyword_query separately for best results; semantic: vague or abstract concepts only; keyword: known exact titles, ISBNs, or precise author names."}},"required":["query","strategy"]}}}]',
    },
    {
        id: "anthropic",
        label: "Anthropic",
        url: "https://api.anthropic.com/v1/messages",
        request_body_template:
            '{"model":"{{model}}","max_tokens":1024,"system":"{{system_prompt}}","messages":"{{messages}}","tools":"{{tool_definitions}}"}',
        response_key: "content.0.text",
        auth_type: "bearer",
        tool_definitions:
            '[{"name":"search_catalogue","description":"Search the library catalogue for books and materials. Always call this before responding to the user.","input_schema":{"type":"object","properties":{"query":{"type":"string","description":"Primary search phrase — used as fallback for both searches when semantic_query or keyword_query are not provided."},"semantic_query":{"type":"string","description":"Optimised for vector/semantic search. A descriptive phrase (2-5 words) capturing the topic and context (e.g. \\"Tudor dynasty English monarchy\\")."},"keyword_query":{"type":"string","description":"Optimised for keyword search. The single most distinctive word or at most two words — shorter is better because keyword search requires ALL words to appear in a record (e.g. \\"Tudor\\" not \\"Tudor dynasty\\")."},"strategy":{"type":"string","enum":["semantic","keyword","hybrid"],"description":"hybrid: use for most searches; provide semantic_query and keyword_query separately for best results; semantic: vague or abstract concepts only; keyword: known exact titles, ISBNs, or precise author names."}},"required":["query","strategy"]}}]',
    },
    {
        id: "ollama",
        label: "Ollama",
        url: "http://localhost:11434/api/chat",
        request_body_template:
            '{"model":"{{model}}","messages":"{{messages}}","stream":false,"tools":"{{tool_definitions}}"}',
        response_key: "message.content",
        auth_type: "none",
        tool_definitions:
            '[{"type":"function","function":{"name":"search_catalogue","description":"Search the library catalogue for books and materials. Always call this before responding to the user.","parameters":{"type":"object","properties":{"query":{"type":"string","description":"Primary search phrase — used as fallback for both searches when semantic_query or keyword_query are not provided."},"semantic_query":{"type":"string","description":"Optimised for vector/semantic search. A descriptive phrase (2-5 words) capturing the topic and context (e.g. \\"Tudor dynasty English monarchy\\")."},"keyword_query":{"type":"string","description":"Optimised for keyword search. The single most distinctive word or at most two words — shorter is better because keyword search requires ALL words to appear in a record (e.g. \\"Tudor\\" not \\"Tudor dynasty\\")."},"strategy":{"type":"string","enum":["semantic","keyword","hybrid"],"description":"hybrid: use for most searches; provide semantic_query and keyword_query separately for best results; semantic: vague or abstract concepts only; keyword: known exact titles, ISBNs, or precise author names."}},"required":["query","strategy"]}}}]',
    },
    {
        id: "custom",
        label: "Custom",
        url: "",
        request_body_template: "",
        response_key: "",
        auth_type: "",
        tool_definitions: "",
    },
];

export default LLM_PROVIDER_PRESETS;
