export class SearchAPIClient {
    constructor(HttpClient) {
        this.llmHttpClient = new HttpClient({
            baseURL: "/api/v1/llm_providers",
        });
        this.embeddingHttpClient = new HttpClient({
            baseURL: "/api/v1/embedding_providers",
        });
        this.agentHttpClient = new HttpClient({
            baseURL: "/api/v1/public/search",
        });
    }

    get llm_providers() {
        return {
            create: llm_provider =>
                this.llmHttpClient.post({
                    endpoint: "",
                    body: llm_provider,
                }),
            delete: id =>
                this.llmHttpClient.delete({
                    endpoint: "/" + id,
                }),
            update: (llm_provider, id) =>
                this.llmHttpClient.put({
                    endpoint: "/" + id,
                    body: llm_provider,
                }),
            get: id =>
                this.llmHttpClient.get({
                    endpoint: "/" + id,
                }),
            getAll: (query, params) =>
                this.llmHttpClient.getAll({
                    endpoint: "/",
                    query,
                    params,
                    headers: {},
                }),
            count: (query = {}) =>
                this.llmHttpClient.count({
                    endpoint:
                        "?" +
                        new URLSearchParams({
                            _page: 1,
                            _per_page: 1,
                            ...(query && { q: JSON.stringify(query) }),
                        }),
                }),
        };
    }

    get embedding_providers() {
        return {
            create: embedding_provider =>
                this.embeddingHttpClient.post({
                    endpoint: "",
                    body: embedding_provider,
                }),
            delete: id =>
                this.embeddingHttpClient.delete({
                    endpoint: "/" + id,
                }),
            update: (embedding_provider, id) =>
                this.embeddingHttpClient.put({
                    endpoint: "/" + id,
                    body: embedding_provider,
                }),
            get: id =>
                this.embeddingHttpClient.get({
                    endpoint: "/" + id,
                }),
            getAll: (query, params) =>
                this.embeddingHttpClient.getAll({
                    endpoint: "/",
                    query,
                    params,
                    headers: {},
                }),
            count: (query = {}) =>
                this.embeddingHttpClient.count({
                    endpoint:
                        "?" +
                        new URLSearchParams({
                            _page: 1,
                            _per_page: 1,
                            ...(query && { q: JSON.stringify(query) }),
                        }),
                }),
        };
    }

    get embedding_config() {
        return {
            get: () => this.embeddingHttpClient.get({ endpoint: "/config" }),
        };
    }

    get search_agent() {
        return {
            converse: (query, conversation, iface) =>
                this.agentHttpClient.post({
                    endpoint: "/agent",
                    body: { query, conversation, interface: iface },
                }),
        };
    }
}

export default SearchAPIClient;
