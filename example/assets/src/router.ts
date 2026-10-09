// A hash router, as small as it can be: `#/products?q=gre` is the path `/products` and the
// query `{ q: "gre" }`. The hash is never sent to the server, which is why the links in
// emails (`/app/#/reset-password?token=…`) put their secret there.
import { computed, ref } from "vue";

const hash = ref(location.hash);
addEventListener("hashchange", () => (hash.value = location.hash));

export const route = computed(() => {
  const [path, query = ""] = hash.value.replace(/^#/, "").split("?");
  return { path: path || "/", query: Object.fromEntries(new URLSearchParams(query)) as Record<string, string> };
});

export const go = (path: string) => {
  location.hash = `#${path}`;
};
