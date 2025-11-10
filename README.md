# autobiography-interactive

Interactive autobiography deployment. Includes full HTML/CSS/JS code, narrative, and interactive features for Gemini, Railway, and public web hosting.

## Google AI Studio quick-start

Use the Gemini API from Google AI Studio to add conversational or generative features to the autobiography experience. The Python client can be initialised with an API key stored either directly in the code or as an environment variable.

```python
from google import genai

client = genai.Client()
response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents="Explain how AI works in a few words",
)
print(response.text)
```

If you need to supply an API key explicitly, either pass it to the client constructor or export it before running your script:

```python
client = genai.Client(api_key="YOUR_API_KEY")
```

```bash
export GOOGLE_API_KEY="YOUR_API_KEY"
```

Additional documentation and API key management tools are available in [Google AI Studio](https://aistudio.google.com/) and the [Gemini API docs](https://ai.google.dev/gemini-api/docs).
