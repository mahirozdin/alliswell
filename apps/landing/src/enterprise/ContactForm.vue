<script setup>
import { computed, ref } from 'vue';

/**
 * The conversation this page exists to start (EE-153).
 *
 * ── WHAT IT DOES TODAY, AND WHY THAT IS NOT A PLACEHOLDER ─────────────────
 *
 * It composes a `mailto:` and opens it. The endpoint that stores a submission
 * and lists it in the operator console is EE-157/EE-159, and wiring the POST is
 * EE-161 — a one-function change, because everything else is already here: the
 * fields, the labels in both languages, the consent gate and the states.
 *
 * The `mailto:` does not leave when the POST arrives. It is simultaneously the
 * JavaScript-off answer, the answer for an installation with no commercial
 * overlay (where the endpoint legitimately 404s), and the answer for somebody
 * who does not want to fill in a form. Removing it to make the form look like
 * the only path would be removing the one path that works unconditionally.
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

const sent = ref(false);

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

function submit() {
  if (!form.value.consent) return;
  // A naive filler trips this; a bot written for this form does not, which is
  // why the real ceilings are on the server.
  if (companyWebsite.value !== '') {
    sent.value = true;
    return;
  }
  window.location.href = mailto.value;
  sent.value = true;
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

      <form class="aw-card contact__form" novalidate @submit.prevent="submit">
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
          <button class="aw-btn" type="submit" :disabled="!form.consent">
            {{ contact.submit }}
          </button>
          <p class="contact__direct">
            {{ contact.orWrite }}
            <a :href="`mailto:${email}`">{{ email }}</a>
          </p>
        </div>

        <p v-if="sent" class="contact__sent" role="status">{{ contact.sent }}</p>
      </form>
    </div>
  </section>
</template>

<style scoped>
.contact__inner {
  max-width: 52rem;
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
