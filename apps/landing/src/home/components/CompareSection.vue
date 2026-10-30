<script setup>
import HomeIcon from './HomeIcon.vue';

/**
 * Six rows from docs/COMPARISON.md, with the places the others are ahead
 * said first (LESSONS web-landing: the table and that document change
 * together). A ruled table, never a grid of tiles.
 */
defineProps({ compare: { type: Object, required: true } });
const ICON = { yes: 'check', no: 'x', partial: 'minus', native: 'check' };
</script>

<template>
  <section id="compare" class="section compare">
    <div class="container">
      <div class="head head--split">
        <h2>{{ compare.title }}</h2>
        <p class="lead">{{ compare.lead }}</p>
      </div>
      <div class="table-wrap" tabindex="0" role="region" :aria-label="compare.caption">
        <table class="table">
          <caption class="visually-hidden">{{ compare.caption }}</caption>
          <thead>
            <tr>
              <td></td>
              <th v-for="(col, i) in compare.columns" :key="col" scope="col" :class="{ 'is-us': i === 0 }">{{ col }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in compare.rows" :key="row[0]">
              <th scope="row">{{ row[0] }}</th>
              <td
                v-for="(cell, i) in row.slice(1)"
                :key="i"
                :class="[`is-${cell}`, { 'is-us': i === 0 }]"
                :data-label="compare.columns[i]"
              >
                <HomeIcon :name="ICON[cell]" :size="18" />
                <span>{{ compare.labels[cell] }}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <a class="text-link" :href="compare.link.href">{{ compare.link.label }}</a>
    </div>
  </section>
</template>
