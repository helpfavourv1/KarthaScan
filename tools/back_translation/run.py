#!/usr/bin/env python3
"""Back-translation screen for the app's ARB files (free, runs on CPU in CI).

For each non-English language: translate every string back to English with NLLB-200
(a different engine from the one that wrote the strings), then compare the result with
the original English string by meaning (English sentence embeddings, cosine similarity).
Low scores are listed as 'look at this one'. A low score is a lead, not a verdict:
free word choice also scores low. High scores do not prove a string sounds natural.
"""
import csv, json, os, re, sys, time

ARB = os.path.join(os.path.dirname(__file__), '..', '..', 'app', 'lib', 'l10n')
OUT = os.environ.get('OUT_DIR', 'bt_out')
LANGS = {
    'es': 'spa_Latn', 'fr': 'fra_Latn', 'de': 'deu_Latn', 'pt': 'por_Latn', 'pt_PT': 'por_Latn',
    'ar': 'arb_Arab', 'hi': 'hin_Deva', 'ja': 'jpn_Jpan', 'ko': 'kor_Hang', 'zh': 'zho_Hans',
    'zh_Hant': 'zho_Hant', 'he': 'heb_Hebr', 'id': 'ind_Latn', 'it': 'ita_Latn', 'nl': 'nld_Latn',
    'tr': 'tur_Latn', 'sv': 'swe_Latn', 'no': 'nob_Latn', 'nn': 'nno_Latn', 'da': 'dan_Latn',
    'fi': 'fin_Latn', 'ms': 'zsm_Latn', 'pl': 'pol_Latn', 'ru': 'rus_Cyrl', 'uk': 'ukr_Cyrl',
    'vi': 'vie_Latn', 'bn': 'ben_Beng', 'th': 'tha_Thai',
}
only = [x for x in os.environ.get('ONLY', '').split(',') if x]
PH = re.compile(r'\{[A-Za-z_][A-Za-z0-9_]*\}')


def load(code):
    d = json.load(open(os.path.join(ARB, f'app_{code}.arb'), encoding='utf-8'))
    return {k: v for k, v in d.items() if not k.startswith('@') and isinstance(v, str)}


def norm(s):
    return PH.sub('5', s)


def usable(s):
    if ', plural' in s or ', select' in s:
        return False
    t = norm(s).strip()
    return len(re.findall(r'[A-Za-zÀ-￿]', t)) >= 3


def main():
    import ctranslate2, transformers
    from sentence_transformers import SentenceTransformer, util
    tok_dir, model_dir = os.environ['NLLB_TOK'], os.environ['NLLB_CT2']
    tr = ctranslate2.Translator(model_dir, device='cpu', compute_type='int8', inter_threads=1, intra_threads=os.cpu_count() or 2)
    emb = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2', device='cpu')
    en = load('en')
    os.makedirs(OUT, exist_ok=True)
    summary = []
    for code, nllb in LANGS.items():
        if only and code not in only:
            continue
        t0 = time.time()
        tr_strings = load(code)
        keys = [k for k in tr_strings if k in en and usable(en[k]) and usable(tr_strings[k])]
        tok = transformers.AutoTokenizer.from_pretrained(tok_dir, src_lang=nllb)
        srcs = [tok.convert_ids_to_tokens(tok.encode(norm(tr_strings[k]))) for k in keys]
        res = tr.translate_batch(srcs, target_prefix=[['eng_Latn']] * len(srcs), beam_size=2, max_batch_size=64, batch_type='examples')
        back = [tok.decode(tok.convert_tokens_to_ids(r.hypotheses[0][1:])) for r in res]
        a = emb.encode([norm(en[k]) for k in keys], convert_to_tensor=True, normalize_embeddings=True)
        b = emb.encode(back, convert_to_tensor=True, normalize_embeddings=True)
        sims = (a * b).sum(dim=1).tolist()
        rows = sorted(zip(sims, keys, back), key=lambda r: r[0])
        with open(os.path.join(OUT, f'{code}.csv'), 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f)
            w.writerow(['score', 'key', 'english', 'translation', 'back_to_english'])
            for s, k, bk in rows:
                w.writerow([f'{s:.3f}', k, en[k], tr_strings[k], bk])
        low = sum(1 for s in sims if s < 0.6)
        summary.append((code, len(keys), low, sum(sims) / max(1, len(sims)), time.time() - t0))
        print(f'{code}: {len(keys)} strings, {low} below 0.6, mean {summary[-1][3]:.3f}, {summary[-1][4]:.0f}s', flush=True)
    with open(os.path.join(OUT, 'summary.csv'), 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['language', 'strings', 'below_0.6', 'mean_score', 'seconds'])
        for r in summary:
            w.writerow([r[0], r[1], r[2], f'{r[3]:.3f}', f'{r[4]:.0f}'])


if __name__ == '__main__':
    main()
