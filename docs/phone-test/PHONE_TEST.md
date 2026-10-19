# KatharScan phone test sheet (Batches A-G, OCR, tray fixes)

Files in this folder: `ocr_sample_<language>.png` (12 pages), `pdf_cjk_sample.txt`, `pdf_complex_sample.txt`, `pdf_hindi_table.csv`.
Every OCR page has the same content in its own language: a title with an invoice number (2026-0417), a date (18 October 2026), an amount (1,284.50) and a short thank-you paragraph.

## A. Text in generated PDFs (Batch G)
What it is about: the PDF library cannot draw Chinese, Japanese, Korean, Hindi, Bengali, Hebrew or Thai text by itself. Chinese, Japanese and Korean fonts are downloaded from the website on first use; the other scripts are drawn as pictures with the phone's own fonts.

1. Convert > pick `pdf_cjk_sample.txt` > PDF. First time (online): the font downloads, the PDF shows three readable paragraphs (Chinese, Japanese, Korean). Expected: no empty boxes.
2. Switch to airplane mode, convert the same file again. Expected: still readable (font is kept on the phone).
3. Convert `pdf_complex_sample.txt` > PDF. Expected: Hindi, Bengali, Hebrew (right to left), Thai and Arabic (right to left) paragraphs all readable. The text is a picture there, so it cannot be selected.
4. Convert `pdf_hindi_table.csv` > PDF. Expected: a table with 3 rows of Hindi names and cities and the amounts.
Fail = empty squares, missing lines, reversed Hebrew/Arabic.

## B. OCR pages
Google Play services scripts (download once, tap the download icon in Settings > OCR Languages first, wait until it says Installed): Chinese, Japanese, Korean, Hindi.
Tesseract scripts (download a few MB on first use from the website): Arabic, Russian, Ukrainian, Greek, Hebrew, Thai, Bengali.

For each page: import the PNG, open it, OCR tool > select the whole page > pick the matching language > Extract. Expected text = the text printed on the page (the same lines as the sample TXT files above for zh, ja, ko, hi, bn, he, th, ar).
Also test: the Russian page scanned with NO language picked (automatic fallback; it only uses languages you installed), and offline after the first run.

Pass marks (what to expect):
- Latin, Russian, Ukrainian, Greek, Hebrew, Bengali: every word right. Known small slip: the number sign in Ukrainian may read as "Мо".
- Arabic: words right; the digits (invoice number, date, amount) are often wrong.
- Thai: main text right; stray symbols on extra lines near the tone marks.
- Chinese, Japanese, Korean, Hindi: not run by me (Google's recognizer is only on the phone), so there is no expected slip list; report any wrong line.

## C. Desktop check I ran (for comparison)
I ran the Tesseract program in my workspace on the same 7 sample PNGs with the exact language files hosted on the website. This was a one-off command, not a saved test. Output:

```
=== arabic (ara)
فاتورة رقم 1'.1-/11ع.
شكراً لطلبكم. سيصل طردكم بتاريخ ‎١8‏ أكتوبر ‎.7١7‏ المبلغ
الإجمالي المستحق: ٠0ر86"١‏ دولار. يرجى الاحتفاظ بهذا
الإيصال لسجلاتكم.
=== russian (rus)
Счёт № 2026-0417
Благодарим за заказ. Ваша посылка
прибудет 18 октября 2026 года. Общая
сумма к оплате: 1 284,50 рублей.
Пожалуйста, сохраните этот чек для своих
записей.
=== ukrainian (ukr)
Рахунок Мо 2026-0417
Дякуємо за замовлення. Вашу посилку буде
доставлено 18 жовтня 2026 року. Загальна
сума до сплати: 1 284,50 гривень. Будь
ласка, збережіть цей чек для своїх записів.
=== greek (ell)
Τιμολόγιο αρ. 2026-0417
Ευχαριστούμε για την παραγγελία σας. Το
δέµα σας θα φτάσει στις 18 Οκτωβρίου 2026.
Συνολικό ποσό πληρωμής: 1.284,50 ευρώ.
Παρακαλούμε φυλάξτε αυτήν την απόδειξη.
=== hebrew (heb)
חשבונית מספר 2026-0417
תודה על הזמנתכם. החבילה שלכם תגיע ב-18
באוקטובר 2026. הסכום הכולל לתשלום: 1,284.50
שקלים. אנא שמרו קבלה זו לרשומותיכם.
=== thai (tha)
ใบแจ้งหนี้เลขที่ 2026-0417
ร      ฉ/     =   เร
ขอบคุณสําหรับคําสังซื้อของคุณ พัสดุจะมาถึงในวันที 18
ตุลาคม 2569 ยอดเงินรวมที่ต้องชําระ 1,284.50 บาท
๕<     ซุซัๆ %,<   ๑
กรุณาเก็บใบเสร็จนีไว้เป็นหลักฐาน
=== bengali (ben)
চালান নম্বর ২০২৬-০৪১৭
আপনার অর্ডারের জন্য ধন্যবাদ। আপনার পার্সেলটি ১৮ অক্টোবর ২০২৬ তারিখে
পৌঁছাবে। মোট প্রদেয় পরিমাণ: ১,২৮৪.৫০ টাকা। অনুগ্রহ করে এই রসিদটি
সংরক্ষণ করুন।
```

## D. Tray fixes
Undo: open a document in the editor, add a watermark, rename the document, add a tag, press undo. Expected: the watermark disappears; the new title and tag stay. Then delete a page in Pages and press undo: the deleted page must not return.
Double tap: tap a tray tool twice quickly (Rotate, Annotate, Convert). Expected: one sheet or one screen, not two.
Delete during edits: add several stamps quickly then delete the document at once. Expected: it stays deleted after restarting the app.
Empty-text export: scan a blank page (or any page with no text), Export > TXT or Word (text only). Expected: the message "This document has no text yet. Run OCR on it first." and no empty file.
