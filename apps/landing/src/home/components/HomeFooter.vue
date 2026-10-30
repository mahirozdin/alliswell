<script setup>
import { computed } from 'vue';

import { company } from '../../company.js';
import { VERSION } from '../../site.js';
import { media } from '../media.js';

/**
 * A mast: the wordmark large over the real links, then the legal line and the
 * credits. The photograph's licence (CC BY) asks for its author, the licence
 * and the changes, which is what the credit line says.
 */
defineProps({ footer: { type: Object, required: true } });
const credit = computed(() => media('photo-fog').credit);
</script>

<template>
  <footer class="mast">
    <div class="container">
      <p class="mast__word">AllisWell</p>
      <p class="mast__line">{{ footer.line }}</p>
      <div class="mast__cols">
        <nav v-for="col in footer.columns" :key="col.title" :aria-label="col.title" class="mast__col">
          <h2>{{ col.title }}</h2>
          <ul>
            <li v-for="link in col.links" :key="link.href">
              <a :href="link.href">{{ link.label }}</a>
            </li>
          </ul>
        </nav>
      </div>
      <div class="mast__legal">
        <p>{{ company.legalName }}, <a :href="`mailto:${company.email}`">{{ company.email }}</a></p>
        <p>{{ footer.notes }}</p>
        <p data-credits>
          {{ footer.photoLabel }}:
          <a :href="credit.source">{{ credit.author }}</a>,
          <a :href="credit.licenceUrl">{{ credit.licence }}</a>, {{ footer.photoChanges }}.
          {{ footer.fontLabel }}: {{ footer.fontCredit }}.
        </p>
        <p>{{ footer.versionLabel }} {{ VERSION }}</p>
      </div>
    </div>
  </footer>
</template>
