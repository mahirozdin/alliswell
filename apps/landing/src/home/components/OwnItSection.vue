<script setup>
import LoopVideo from './LoopVideo.vue';

/**
 * Self-hosting, on a change of paper: the loop of the containers coming up
 * on the left (the page's one mirror), the command and three facts on the
 * right. The command is the real one from docs/SELF-HOSTING.md.
 */
defineProps({ own: { type: Object, required: true }, ui: { type: Object, required: true } });
</script>

<template>
  <section id="self-host" class="section band own">
    <div class="container">
      <div class="head head--split">
        <h2>{{ own.title }}</h2>
        <p class="lead">{{ own.lead }}</p>
      </div>
      <div class="split split--mirror">
        <div class="glass split__visual">
          <LoopVideo :name="own.media" :alt="own.alt" :labels="ui" />
        </div>
        <div class="split__text">
          <figure class="command">
            <figcaption>{{ own.commandLabel }}</figcaption>
            <pre><code>{{ own.command }}</code></pre>
          </figure>
          <ul class="facts">
            <li v-for="point in own.points" :key="point">{{ point }}</li>
          </ul>
          <a class="text-link" :href="own.link.href">{{ own.link.label }}</a>
        </div>
      </div>
    </div>
  </section>
</template>
