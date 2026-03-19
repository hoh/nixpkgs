from kittentts import KittenTTS, __version__
from kittentts.onnx_model import TextCleaner, chunk_text
from kittentts.preprocess import TextPreprocessor


def test_exports_and_version():
    assert callable(KittenTTS)
    assert __version__ == "0.8.1"


def test_chunk_text_preserves_chunk_limit():
    assert chunk_text("one two three four five", max_len=10) == [
        "one two,",
        "three four,",
        "five,",
    ]


def test_text_cleaner_ignores_unknown_symbols():
    tokens = TextCleaner()("Hi🙂")
    assert len(tokens) == 2
    assert all(isinstance(token, int) for token in tokens)


def test_preprocessor_expands_common_tts_inputs():
    text = TextPreprocessor(remove_punctuation=False)(
        "Meet me at 3:30pm with $5 and 50% battery."
    )

    assert "three thirty pm" in text
    assert "five dollars" in text
    assert "fifty percent" in text
