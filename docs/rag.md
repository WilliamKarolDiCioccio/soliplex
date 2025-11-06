# Retrieval-Augmented Generation (RAG) Database

Soliplex depends on the `haiku-rag`
[library](https://pypi.org/project/haiku-rag) to manage its
retrieval-augmented generation (RAG) searches.  That library stores its
extracted documents / chunks / embeddings in
[LanceDB](https://lancedb.com/) databases.

The example installation of Soliplex uses the Soliplex documentation as its
RAG corpus, and expects that database to be created at `db/rag/rag.lancedb`.


## Adding a single document

```bash
export OLLAMA_BASE_URL=<your Ollama server / port>
haiku-rag --config example/haiku.rag.yaml \
  add-src --db db/rag/rag.lancedb docs/index.md
...
Document <UUID> added successfully.
```

## Adding all documents in a directory

```bash
export OLLAMA_BASE_URL=<your Ollama server / port>
haiku-rag --config example/haiku.rag.yaml \
  add-src --db db/rag/rag.lancedb docs/
...
17 documents added successfully.
```
