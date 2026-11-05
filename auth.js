import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm'

const supabase = createClient(
    'https://vichweflmhhepwkwdzdl.supabase.co',
    'sb_publishable_rvW7gmWbDiwm_0IB7L3rnQ_ulE6vcwG'
)

const signInForm = document.querySelector('#sign-in-form')
const signUpForm = document.querySelector('#sign-up-form')
const message = document.querySelector('#auth-message')

if (message && new URLSearchParams(window.location.search).has('registered')) {
    const needsConfirmation = new URLSearchParams(window.location.search).has('confirm')
    showMessage(needsConfirmation
        ? 'Account created. Confirm your email, then sign in.'
        : 'Account created. Enter your email and password to sign in.')
}

function showMessage(text, isError = false) {
    if (!message) return
    message.textContent = text
    message.style.color = isError ? '#ffb4b4' : ''
}

if (signInForm) {
    signInForm.addEventListener('submit', async (event) => {
        event.preventDefault()
        const button = signInForm.querySelector('button[type="submit"]')
        button.disabled = true
        showMessage('Signing in…')

        const { error } = await supabase.auth.signInWithPassword({
            email: document.querySelector('#E').value.trim(),
            password: document.querySelector('#P').value
        })

        if (error) {
            showMessage(error.message, true)
            button.disabled = false
            return
        }
        window.location.assign('homepage.html')
    })
}

if (signUpForm) {
    signUpForm.addEventListener('submit', async (event) => {
        event.preventDefault()
        const button = signUpForm.querySelector('button[type="submit"]')
        const password = document.querySelector('#P').value
        const confirmPassword = document.querySelector('#C').value

        if (password !== confirmPassword) {
            showMessage('The passwords do not match.', true)
            return
        }

        button.disabled = true
        showMessage('Creating your account…')

        const { data, error } = await supabase.auth.signUp({
            email: document.querySelector('#E').value.trim(),
            password,
            options: {
                data: { full_name: document.querySelector('#F').value.trim() },
                emailRedirectTo: new URL('homepage.html', window.location.href).href
            }
        })

        if (error) {
            showMessage(error.message, true)
            button.disabled = false
            return
        }

        const loginUrl = new URL('contact=styled.html', window.location.href)
        loginUrl.searchParams.set('registered', '1')
        if (!data.session) loginUrl.searchParams.set('confirm', '1')
        window.location.assign(loginUrl)
    })
}
