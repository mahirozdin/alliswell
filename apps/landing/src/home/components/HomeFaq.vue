<script setup>
/** The objections, hardest first, as closed rows (Hallmark: Rows). */
defineProps({ faq: { type: Object, required: true } });
</script>

<template>
  <section id="faq" class="section faq">
    <div class="container faq__grid">
      <div class="head">
        <h2>{{ faq.title }}</h2>
      </div>
      <div class="faq__rows">
        <details v-for="item in faq.items" :key="item.q" class="faq__row">
          <summary>
            <span>{{ item.q }}</span>
          </summary>
          <div class="faq__answer"><p>{{ item.a }}</p></div>
        </details>
      </div>
    </div>
  </section>
</template>
