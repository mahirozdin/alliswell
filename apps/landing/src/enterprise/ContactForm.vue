<script setup>
import { computed, ref } from 'vue';

import { OUTCOME, payloadFrom, sendEnquiry } from './submit.js';

/**
 * The conversation this page exists to start (EE-153, wired in EE-161).
 *
 * ── THE `mailto:` DID NOT LEAVE WHEN THE POST ARRIVED ─────────────────────
 *
 * It is simultaneously the JavaScript-off answer, the answer for an
 * installation with no commercial overlay (where the endpoint legitimately
 * 404s), and the answer for somebody who would rather not fill in a form.
 * Removing it to make the POST look like the only path would remove the one
 * path that works unconditionally.
 *
 * ── FOUR OUTCOMES, AND ONLY ONE OF THEM TAKES THE FORM AWAY ───────────────
 *
 * A 404 is not an error here. It says this deployment has no sales desk, which
 * is a fact about the deployment rather than a failure of the request — so the
 * form is REPLACED by the address, permanently, rather than offering a retry
 * that will never work.
 *
 * Everything else keeps the form exactly as the reader left it. Somebody who
 * typed six fields and hit a rate limit must not lose them; that is the
 * difference between an error message and an insult.
 *
 * ── THE CONSENT BOX IS NOT DECORATION ─────────────────────────────────────
 *
 * This is a Turkish B2B form and the first thing on this site that would collect
 * a name, a company, an address and a phone number from somebody who is not a
 * customer — under explicit consent (açık rıza) rather than a contract. So the
 * box is required to submit, and it links to the notice beside it: a tick with
 * nothing to read is agreement to nothing.
 */
const props = defineProps({
  contact: { type: Object, required: true },
  /** Where the composed message goes, and the address printed in the prose. */
  email: { type: String, required: true },
  /** Which acknowledgement the sender gets — the page they read decides it. */
  lang: { type: String, required: true },
});

const form = ref({
  name: '',
  company: '',
  workEmail: '',
  phone: '',
  seats: '',
  units: '',
  packageInterest: '',
  message: '',
  consent: false,
});

/**
 * The honeypot. Hidden from EVERY reader rather than just the sighted one —
 * `hidden` plus `aria-hidden` plus `tabindex="-1"` takes it out of the visual
 * order, the accessibility tree and the tab order at once. The portal's own
 * trap is built the same way and says why: hiding a field with CSS leaves one
 * a screen reader announces and a keyboard reaches, which is an accessibility
 * bug dressed as a security control.
 *
 * Nothing reads it yet; EE-157 does, on the server, where it counts.
 */
const companyWebsite = ref('');

/** `null` until the first attempt; then one of `OUTCOME`. */
const outcome = ref(null);
const busy = ref(false);

/** The 404 answer, and the only one that removes the form. */
const noDesk = computed(() => outcome.value === OUTCOME.noDesk);
const sent = computed(() => outcome.value === OUTCOME.sent);
/** Anything the reader could act on, said in their language. */
const problem = computed(() =>
  outcome.value && outcome.value !== OUTCOME.sent && outcome.value !== OUTCOME.noDesk
    ? props.contact.states[outcome.value]
    : null,
);

/**
 * The same enquiry as an e-mail, pre-filled.
 *
 * Its home is now the 404 branch, and that is where it earns its keep: the
 * reader has just filled in six fields and is being told this installation has
 * no sales desk. Handing them a bare address would throw away everything they
 * typed — the composed one carries it into their mail client instead.
 *
 * The always-visible "or write to" line keeps the bare address, because before
 * anybody types, a pre-filled message is a page of empty labels.
 */
const mailto = computed(() => {
  const f = form.value;
  const lines = [
    `${props.contact.fields.name.label}: ${f.name}`,
    `${props.contact.fields.company.label}: ${f.company}`,
    `${props.contact.fields.workEmail.label}: ${f.workEmail}`,
    f.phone && `${props.contact.fields.phone.label}: ${f.phone}`,
    f.seats && `${props.contact.fields.seats.label}: ${f.seats}`,
    f.units && `${props.contact.fields.units.label}: ${f.units}`,
    f.packageInterest && `${props.contact.fields.packageInterest.label}: ${f.packageInterest}`,
    '',
    f.message,
  ].filter((l) => l !== false && l !== undefined && l !== null);
  const subject = `${props.contact.mailSubject} — ${f.company || f.name}`;
  return (
    `mailto:${props.email}?subject=${encodeURIComponent(subject)}` +
    `&body=${encodeURIComponent(lines.join('\n'))}`
  );
});

async function submit() {
  if (!form.value.consent || busy.value) return;
  busy.value = true;
  outcome.value = null;
  try {
    // The trap travels WITH the payload rather than short-circuiting here. A
    // client-side refusal tells the bot's author which field to leave alone
    // next time; the server answers 201 and writes nothing, so a trapped
    // submission is indistinguishable from a real one on the wire.
    const result = await sendEnquiry(
      payloadFrom(form.value, props.lang, companyWebsite.value),
    );
    outcome.value = result;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <section v-reveal class="aw-section contact">
    <div class="aw-shell contact__inner">
      <header class="contact__head">
        <p v-if="contact.eyebrow" class="aw-eyebrow">{{ contact.eyebrow }}</p>
        <h2>{{ contact.title }}</h2>
        <p class="aw-lede">{{ contact.lede }}</p>
      </header>

      <!-- The 404 answer. Not an error state: this installation has no sales
           desk, so the form is replaced by the one route that always works. -->
      <div v-if="noDesk" class="aw-card contact__nodesk">
        <p>{{ contact.states.noDesk }}</p>
        <p class="contact__nodesk-address">
          <a :href="mailto">{{ email }}</a>
        </p>
      </div>

      <form v-else class="aw-card contact__form" novalidate @submit.prevent="submit">
        <div class="contact__row">
          <label class="contact__field">
            <span>{{ contact.fields.name.label }}</span>
            <input v-model="form.name" type="text" required maxlength="120" autocomplete="name" />
          </label>
          <label class="contact__field">
            <span>{{ contact.fields.company.label }}</span>
            <input
              v-model="form.company"
              type="text"
              required
              maxlength="160"
              autocomplete="organization"
            />
          </label>
        </div>

        <div class="contact__row">
          <label class="contact__field">
            <span>{{ contact.fields.workEmail.label }}</span>
            <input
              v-model="form.workEmail"
              type="email"
              required
              maxlength="320"
              autocomplete="email"
            />
          </label>
          <label class="contact__field">
            <span>{{ contact.fields.phone.label }}</span>
            <input v-model="form.phone" type="tel" maxlength="32" autocomplete="tel" />
          </label>
        </div>

        <div class="contact__row">
          <label class="contact__field">
            <span>{{ contact.fields.seats.label }}</span>
            <input v-model="form.seats" type="number" min="1" inputmode="numeric" />
          </label>
          <label class="contact__field">
            <span>{{ contact.fields.units.label }}</span>
            <input v-model="form.units" type="number" min="1" inputmode="numeric" />
          </label>
        </div>

        <label class="contact__field">
          <span>{{ contact.fields.packageInterest.label }}</span>
          <select v-model="form.packageInterest">
            <option value="">{{ contact.fields.packageInterest.placeholder }}</option>
            <option v-for="o in contact.fields.packageInterest.options" :key="o" :value="o">
              {{ o }}
            </option>
          </select>
        </label>

        <label class="contact__field">
          <span>{{ contact.fields.message.label }}</span>
          <textarea v-model="form.message" rows="5" maxlength="4000"></textarea>
        </label>

        <!-- The trap. See the script's note on why it is hidden three ways. -->
        <div hidden aria-hidden="true">
          <label for="company_website">{{ contact.fields.honeypot }}</label>
          <input id="company_website" v-model="companyWebsite" type="text" tabindex="-1" />
        </div>

        <label class="contact__consent">
          <input v-model="form.consent" type="checkbox" required />
          <span>
            {{ contact.consent.text }}
            <a :href="contact.consent.href">{{ contact.consent.linkLabel }}</a>
          </span>
        </label>

        <div class="contact__actions">
          <button class="aw-btn" type="submit" :disabled="!form.consent || busy">
            {{ busy ? contact.sending : contact.submit }}
          </button>
          <p class="contact__direct">
            {{ contact.orWrite }}
            <a :href="`mailto:${email}`">{{ email }}</a>
          </p>
        </div>

        <p v-if="sent" class="contact__sent" role="status">{{ contact.sent }}</p>
        <!-- `alert`, not `status`: the reader has to act on this one, and the
             form below it still holds everything they typed. -->
        <p v-else-if="problem" class="contact__problem" role="alert">{{ problem }}</p>
      </form>
    </div>
  </section>
</template>

<style scoped>
.contact__inner {
  max-width: 52rem;
}

.contact__nodesk {
  display: grid;
  gap: 0.6rem;
  padding: clamp(1.4rem, 3vw, 2.1rem);
}

.contact__nodesk-address {
  font-size: 1.1rem;
  font-weight: 600;
}

/**
 * `--aw-error`, which is the token this stylesheet actually defines, and it is
 * theme-aware (#d70015 light, #ff5147 dark).
 *
 * The first draft invented `--aw-danger` and fell through to a hard-coded
 * `#b3261e`. Measured in the browser rather than eyeballed: 2.48:1 against the
 * card in dark mode, well under AA's 4.5 — on the one message carrying
 * `role="alert"`, the single line a reader MUST be able to read. It looked
 * fine in the screenshot, which is the whole argument for measuring.
 */
.contact__problem {
  margin: 0;
  padding: 0.7rem 0.9rem;
  border-radius: 0.6rem;
  background: color-mix(in oklab, var(--aw-error) 12%, transparent);
  color: var(--aw-error);
  font-size: 0.95rem;
}

.contact__head {
  margin-bottom: 1.9rem;
}

.contact__form {
  display: grid;
  gap: 1.1rem;
  padding: clamp(1.4rem, 3vw, 2.1rem);
}

.contact__row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
  gap: 1.1rem;
}

.contact__field {
  display: grid;
  gap: 0.4rem;
  font-size: 0.92rem;
  font-weight: 600;
}

.contact__field input,
.contact__field select,
.contact__field textarea {
  font: inherit;
  font-weight: 400;
  padding: 0.7rem 0.85rem;
  border-radius: 12px;
  border: 1px solid var(--aw-hairline);
  background: var(--aw-surface-2);
  color: var(--aw-text);
  width: 100%;
}

.contact__field textarea {
  resize: vertical;
  min-height: 7rem;
}

.contact__consent {
  display: flex;
  gap: 0.65rem;
  align-items: flex-start;
  font-size: 0.9rem;
  color: var(--aw-text-dim);
}

.contact__consent input {
  margin-top: 0.22rem;
  flex-shrink: 0;
}

.contact__actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 1rem;
}

.contact__direct {
  margin: 0;
  color: var(--aw-text-dim);
  font-size: 0.9rem;
}

.contact__sent {
  margin: 0;
  color: var(--aw-text);
  font-size: 0.92rem;
}
</style>
