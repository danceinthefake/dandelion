# 26 — The console, in a real browser

Claim: The Vue console does what the service does, and a person can use it. A real Chromium drives the console against the 3-node cluster, from a new account to a phone-sized screen. Each step below is a line of [`run.log`](run.log) that had to be true.

![the console, driven by the proof](console.gif)

1. A new customer. The customer creates an account. The console signs the customer in and says that the address is not confirmed. The customer opens the link from the email. The link opens the console and confirms the address, and the warning goes away. A customer sees Products and Files and does not see the staff pages. A staff page that the customer opens by hand says that it is for staff.
2. A forgotten password. A request shows the same words for any address. The page of the link refuses a password that is too short and says why. It refuses two passwords that differ. It accepts a good password. The page refuses the same link a second time. The old password no longer signs in, and the new password does.
3. Guessing. Five wrong passwords lock the address. The service refuses even the right password, and the page says for how long (15 minutes).
4. Staff. An order made in the form appears in the live list.
   - Products: If the staff types "gre", the page finds "Green tea" and no button is pressed. The page accepts a typo and says that the names are only close. If the staff types fast, the page shows the answer for what was typed last. The page finds a product that was just added at once, and it highlights the word of its description. A name with HTML in it shows as the characters typed, and nothing becomes markup. A rename is found by the new name. A removed product is gone from the next search.
   - Settings: The switch pauses new orders, and the order form then says so. The switch opens the orders again.
   - Audit log: It shows the switch and the product and who did them. It filters to settings.
   - Webhooks: The staff adds an endpoint, and the page shows its signing secret one time. A reload does not show it.
   - Files: The staff uploads a 2 MB file, and the page lists it with its type. The staff downloads it as the very same bytes. The page refuses a program with the name `.png`, because the bytes decide. The staff removes a file.
5. A phone. At 390 px wide, none of the six pages is wider than the screen.

Screenshots of each page: [`orders`](orders.png), [`products`](products.png), [`settings`](settings.png), [`audit`](audit.png), [`webhooks`](webhooks.png), [`files`](files.png), and the account pages ([`register`](register.png), [`unconfirmed`](unconfirmed.png), [`forgot`](forgot.png), [`reset`](reset.png), [`locked`](locked.png)). The phone screenshot is [`phone`](phone.png).

Code: `example/assets/src/` has `App.vue`, `pages/*.vue`, `api.ts`, `router.ts`, and `highlight.ts` (with `highlight.test.ts`, which `npm test` runs). See DESIGN.md §10.24.

Negative controls ([`xss.log`](../controls/xss.log), [`leakyorders.log`](../controls/leakyorders.log)): If the page shows a product name with `v-html`, the name becomes markup (the `<i>` is italic) and the proof stops. Without the `v-show` that hides the orders list, the list stays on top of every other page and the proof stops.

Found by running it: Each of these was a bug in the first version of the console. The browser and its screenshots found them, and we fixed them.
- The orders page is a fragment (two sections), and `v-show` cannot hide a fragment. The orders list showed on every page.
- A confirm dialog that nothing tells to close stays open over the page after "Remove".
- A settings switch showed "on" before the settings loaded.
- nginx refused any body over 1 MB. The 5 MB file limit of the app was therefore not reachable through the load balancer. The "7.5 MB is refused" check of the uploads proof was the answer of nginx and not of the app. It now also tests 6.1 MB, which only the app can refuse.
- A 503 showed as "HTTP 503". It now says that the service is busy.

Not shown: other browsers, assistive technology, slow networks, and the emailed pages in a real mail client (see [LIMITS.md](../LIMITS.md)).

To run it again, run `PLAYWRIGHT=… evidence/record.sh console`. This takes about 2 minutes and needs Playwright and ffmpeg. To run the controls, run `ONLY=xss evidence/record.sh controls` and `ONLY=leakyorders …`.
