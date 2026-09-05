import SwiftUI

struct AuthView: View {
    @Environment(\.appEnv) private var appEnv
    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSignUp = false
    @State private var isForgotPassword = false

    private var auth: AuthService { appEnv.auth }

    var body: some View {
        if auth.isRecoveringPassword {
            setNewPasswordView
        } else if auth.pendingEmailConfirmation {
            mailNoticeView(
                title: "Check your email",
                bodyText: "We sent a confirmation link to\n\(auth.pendingEmail)",
                actionTitle: "Resend email",
                action: { await auth.resendConfirmation() },
                backTitle: "Back to Sign In",
                onBack: { auth.cancelConfirmation() }
            )
        } else if auth.pendingPasswordReset {
            mailNoticeView(
                title: "Check your email",
                bodyText: "We sent a password reset link to\n\(auth.pendingEmail)",
                actionTitle: nil,
                action: nil,
                backTitle: "Back to Sign In",
                onBack: {
                    auth.cancelPasswordReset()
                    isForgotPassword = false
                }
            )
        } else {
            formView
        }
    }

    private func mailNoticeView(
        title: String,
        bodyText: String,
        actionTitle: String?,
        action: (() async -> Void)?,
        backTitle: String,
        onBack: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.surfaceDoodh.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                wordmark
                Spacer().frame(height: 48)
                Image(systemName: "envelope.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.brandSaag)
                Spacer().frame(height: 24)
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.inkKohl)
                Spacer().frame(height: 10)
                Text(bodyText)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.inkKohlSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Samaan.Space.md)
                if let actionTitle, let action {
                    Spacer().frame(height: 40)
                    Button {
                        Task { await action() }
                    } label: {
                        Group {
                            if auth.isLoading {
                                ProgressView().tint(Color.surfaceDoodh)
                            } else {
                                Text(actionTitle)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.surfaceDoodh)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.brandSaag, in: RoundedRectangle(cornerRadius: Samaan.Radius.md))
                    }
                    .disabled(auth.isLoading)
                    .padding(.horizontal, Samaan.Space.md)
                }
                if let error = auth.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentAnaar)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Samaan.Space.md)
                        .padding(.top, 12)
                }
                Spacer().frame(height: 16)
                Button(action: onBack) {
                    Text(backTitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.brandSaag)
                }
                Spacer()
            }
        }
    }

    private var wordmark: some View {
        VStack(spacing: 6) {
            Text("Samaan")
                .font(.cormorant(size: 52, weight: .bold))
                .foregroundStyle(Color.brandSaag)
            Text("سامان")
                .font(.custom("NotoNastaliqUrdu-Regular", size: 22))
                .foregroundStyle(Color.inkKohlSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private var formView: some View {
        ZStack {
            Color.surfaceDoodh.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 72)

                    wordmark

                    Spacer().frame(height: 40)

                    VStack(spacing: 14) {
                        labeledField(title: "EMAIL") {
                            ZStack(alignment: .leading) {
                                if email.isEmpty {
                                    Text("you@example.com")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.inkKohlSoft)
                                        .padding(.horizontal, 14)
                                        .allowsHitTesting(false)
                                }
                                TextField("", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.inkKohl)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 13)
                            }
                            .background(Color.surfaceAtta, in: RoundedRectangle(cornerRadius: Samaan.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Samaan.Radius.md)
                                    .stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1)
                            )
                        }

                        if !isForgotPassword {
                            labeledField(title: "PASSWORD") {
                                SecureField("••••••••", text: $password)
                                    .textContentType(isSignUp ? .newPassword : .password)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.inkKohl)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 13)
                                    .background(Color.surfaceAtta, in: RoundedRectangle(cornerRadius: Samaan.Radius.md))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Samaan.Radius.md)
                                            .stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1)
                                    )
                            }
                        }

                        if let error = auth.errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(Color.accentAnaar)
                                    .font(.system(size: 13))
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.accentAnaar)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, Samaan.Space.md)

                    if !isSignUp && !isForgotPassword {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isForgotPassword = true
                                    auth.errorMessage = nil
                                }
                            } label: {
                                Text("Forgot password?")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.brandSaag)
                            }
                        }
                        .padding(.horizontal, Samaan.Space.md)
                        .padding(.top, 10)
                    }

                    Spacer().frame(height: 24)

                    Button {
                        Task {
                            if isForgotPassword {
                                await auth.resetPassword(email: email)
                            } else if isSignUp {
                                await auth.signUp(email: email, password: password)
                            } else {
                                await auth.signIn(email: email, password: password)
                            }
                        }
                    } label: {
                        Group {
                            if auth.isLoading {
                                ProgressView().tint(Color.surfaceDoodh)
                            } else {
                                Text(primaryLabel)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(Color.surfaceDoodh)
                        .background(
                            primaryDisabled
                                ? Color.brandSaag.opacity(0.45)
                                : Color.brandSaag,
                            in: RoundedRectangle(cornerRadius: Samaan.Radius.md)
                        )
                    }
                    .disabled(primaryDisabled || auth.isLoading)
                    .padding(.horizontal, Samaan.Space.md)

                    Spacer().frame(height: 20)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isForgotPassword {
                                isForgotPassword = false
                            } else {
                                isSignUp.toggle()
                            }
                            auth.errorMessage = nil
                        }
                    } label: {
                        if isForgotPassword {
                            Text("Back to Sign In")
                                .foregroundStyle(Color.brandSaag)
                        } else {
                            Text(
                                "\(Text(isSignUp ? "Already have an account? " : "Don't have an account? ").foregroundStyle(Color.inkKohlSoft))\(Text(isSignUp ? "Sign In" : "Create account").foregroundStyle(Color.brandSaag))"
                            )
                        }
                    }
                    .font(.system(size: 14))

                    Spacer().frame(height: 48)
                }
            }
        }
    }

    private var setNewPasswordView: some View {
        ZStack {
            Color.surfaceDoodh.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                wordmark
                Spacer().frame(height: 40)
                Text("Set a new password")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.inkKohl)
                Spacer().frame(height: 8)
                Text("Choose something you'll remember. At least 6 characters.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.inkKohlSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Samaan.Space.md)

                VStack(spacing: 14) {
                    labeledField(title: "NEW PASSWORD") {
                        SecureField("••••••••", text: $newPassword)
                            .textContentType(.newPassword)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.inkKohl)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(Color.surfaceAtta, in: RoundedRectangle(cornerRadius: Samaan.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Samaan.Radius.md)
                                    .stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1)
                            )
                    }
                    labeledField(title: "CONFIRM") {
                        SecureField("••••••••", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.inkKohl)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(Color.surfaceAtta, in: RoundedRectangle(cornerRadius: Samaan.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Samaan.Radius.md)
                                    .stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1)
                            )
                    }
                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentAnaar)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Samaan.Space.md)
                .padding(.top, 28)

                Spacer().frame(height: 24)
                Button {
                    Task {
                        guard newPassword.count >= 6 else {
                            auth.errorMessage = "Use a password with at least 6 characters."
                            return
                        }
                        guard newPassword == confirmPassword else {
                            auth.errorMessage = "Those passwords don't match."
                            return
                        }
                        await auth.updatePassword(newPassword)
                    }
                } label: {
                    Group {
                        if auth.isLoading {
                            ProgressView().tint(Color.surfaceDoodh)
                        } else {
                            Text("Save password")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(Color.surfaceDoodh)
                    .background(Color.brandSaag, in: RoundedRectangle(cornerRadius: Samaan.Radius.md))
                }
                .disabled(auth.isLoading || newPassword.isEmpty || confirmPassword.isEmpty)
                .padding(.horizontal, Samaan.Space.md)
                Spacer()
            }
        }
    }

    private var primaryLabel: String {
        if isForgotPassword { return "Send reset link" }
        return isSignUp ? "Create Account" : "Sign In"
    }

    private var primaryDisabled: Bool {
        if isForgotPassword { return email.isEmpty }
        return email.isEmpty || password.isEmpty
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.inkKohlSoft)
                .kerning(0.8)
            content()
        }
    }
}

#Preview {
    AuthView()
        .environment(\.appEnv, AppEnvironment(modelContainer: .preview))
}
