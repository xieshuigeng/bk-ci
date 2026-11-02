<template>
    <img
        v-if="showRemote"
        :src="logoUrl"
        @error="handleLoadError"
    >
    <Logo
        v-else
        :name="name"
        :size="size"
    />
</template>

<script setup>
    import { computed, ref, watch } from 'vue'
    import { logoFailCache } from './hooks/logoFailCache'
    import Logo from './Logo'

    const props = defineProps({
        logoUrl: {
            type: String,
            default: ''
        },
        name: String,
        size: {
            type: [String, Number],
            default: 18
        }
    })

    // 失败态按 logoUrl 维度缓存在模块级 Set（会话内有效），同 URL 的其余元素直接走回退、不再发请求
    const localFailed = ref(logoFailCache.has(props.logoUrl))

    watch(() => props.logoUrl, (url) => {
        localFailed.value = logoFailCache.has(url)
    })

    const showRemote = computed(() => !!props.logoUrl && !localFailed.value)

    function handleLoadError () {
        logoFailCache.add(props.logoUrl)
        localFailed.value = true
    }
</script>
