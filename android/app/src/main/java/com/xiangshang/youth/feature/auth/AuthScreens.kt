package com.xiangshang.youth.feature.auth

import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiangshang.youth.R
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.shared.component.AppScaffold
import kotlinx.coroutines.delay

@Composable
fun SplashScreen(onFinished: () -> Unit, canFinish: () -> Boolean = { true }) {
    val reduceMotion = LocalReduceMotion.current
    val transition = rememberInfiniteTransition(label = "splash-breathe")
    val scale by transition.animateFloat(1f, if (reduceMotion) 1f else 1.025f, infiniteRepeatable(tween(1500, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "splash-scale")
    LaunchedEffect(Unit) {
        delay(2000)
        while (!canFinish()) delay(120)
        onFinished()
    }
    Image(painter = painterResource(R.drawable.launch_poster), contentDescription = "向上少年启动页", modifier = Modifier.fillMaxSize().scale(scale), contentScale = ContentScale.Crop)
}

@Composable
fun LoginScreen(
    onLogin: () -> Unit,
    onRegister: () -> Unit,
    onForgotPassword: () -> Unit = {},
    loading: Boolean = false,
    serverError: String? = null,
    onClearError: () -> Unit = {}
) {
    val reduceMotion = LocalReduceMotion.current
    val transition = rememberInfiniteTransition(label = "login-landscape")
    val landscapeScale by transition.animateFloat(1f, if (reduceMotion) 1f else 1.035f, infiniteRepeatable(tween(5400, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "landscape-scale")
    var method by rememberSaveable { mutableIntStateOf(0) }
    var phone by rememberSaveable { mutableStateOf("") }
    var account by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var agreement by rememberSaveable { mutableStateOf(false) }
    var codeSent by rememberSaveable { mutableStateOf(false) }
    var codeCountdown by rememberSaveable { mutableIntStateOf(0) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var legalDocument by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(codeCountdown > 0) {
        while (codeSent && codeCountdown > 0) {
            delay(1000)
            codeCountdown -= 1
        }
    }
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF76B8F7), Color(0xFFEFF8FF))))) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.padding(top = 34.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("向上少年", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Black)
                Text("身心健康智慧平台", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Black)
                Text("科学评估 · 精准干预 · 守护3-18岁青少年身心健康", color = Color(0xFFFFBD2E), fontSize = 9.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp).background(Color.White.copy(.17f), CircleShape))
            }
            Spacer(Modifier.height(10.dp))
            Surface(Modifier.fillMaxWidth().padding(horizontal = 10.dp), color = Color.White, shape = RoundedCornerShape(26.dp), shadowElevation = 4.dp) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { Text("登录开启成长之旅", color = Navy, fontSize = 14.sp, fontWeight = FontWeight.Bold); Spacer(Modifier.width(7.dp)); Icon(Icons.Filled.WbSunny, null, tint = Color(0xFFFFBD2E), modifier = Modifier.size(20.dp)) }
                    Column(verticalArrangement = Arrangement.spacedBy(7.dp), modifier = Modifier.fillMaxWidth()) {
                        LoginButton("微信登录", Icons.Filled.Chat, Blue, Color.White, { method = 0; error = null; onClearError() })
                        LoginButton("手机号登录", Icons.Filled.PhoneIphone, Blue, Color.White, { method = 1; error = null; onClearError() }, outlined = method != 1)
                        LoginButton("账号密码登录", Icons.Filled.Person, Color(0xFFFFB92E), Color(0xFF765522), { method = 2; error = null; onClearError() }, outlined = method != 2)
                    }
                    if (method == 1) {
                        OutlinedTextField(value = phone, onValueChange = { phone = it; error = null; onClearError() }, label = { Text("手机号") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), singleLine = true, modifier = Modifier.fillMaxWidth())
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            OutlinedTextField(value = code, onValueChange = { code = it; error = null; onClearError() }, label = { Text("短信验证码") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true, modifier = Modifier.weight(1f))
                            TextButton(onClick = { if (phone.filter(Char::isDigit).length != 11) error = "请先填写 11 位手机号。" else { codeSent = true; codeCountdown = 60; code = "1234" } }, enabled = codeCountdown == 0) { Text(if (codeCountdown > 0) "${codeCountdown}s 后重试" else if (codeSent) "重新获取" else "获取验证码", fontSize = 11.sp) }
                        }
                    } else if (method == 2) {
                        OutlinedTextField(value = account, onValueChange = { account = it; error = null; onClearError() }, label = { Text("账号 / 手机号") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(value = password, onValueChange = { password = it; error = null; onClearError() }, label = { Text("登录密码（至少 6 位）") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), singleLine = true, modifier = Modifier.fillMaxWidth())
                    }
                    Button(onClick = {
                        when {
                            !agreement -> error = "请先阅读并同意用户协议和儿童隐私政策。"
                            method == 0 -> onLogin()
                            method == 1 && phone.filter(Char::isDigit).length != 11 -> error = "请输入有效的 11 位手机号。"
                            method == 1 && !codeSent -> error = "请先获取短信验证码。"
                            method == 1 && code.length < 4 -> error = "请输入短信验证码。"
                            method == 2 && account.isBlank() -> error = "请输入账号或手机号。"
                            method == 2 && password.length < 6 -> error = "密码至少需要 6 位。"
                            else -> onLogin()
                        }
                    }, enabled = !loading, modifier = Modifier.fillMaxWidth().height(44.dp), shape = CircleShape) {
                        if (loading) CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp)) else Icon(if (method == 0) Icons.Filled.VerifiedUser else Icons.Filled.Login, null)
                        Spacer(Modifier.width(7.dp)); Text(if (loading) "正在登录…" else if (method == 0) "微信授权登录" else "登录", fontWeight = FontWeight.Bold)
                    }
                    (error ?: serverError)?.let { Text(it, color = Color.Red, fontSize = 10.sp) }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        TextButton(onClick = onRegister, contentPadding = PaddingValues(0.dp)) { Text("注册新账号", color = Blue, fontSize = 11.sp) }
                        TextButton(onClick = onForgotPassword, contentPadding = PaddingValues(0.dp)) { Text("忘记密码？", color = Color.Gray, fontSize = 11.sp) }
                    }
                    Column(Modifier.fillMaxWidth().padding(top = 5.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { LoginCheck("专业身心测评与科学健康干预", "体质评估 · 科学干预"); LoginCheck("提供专属解决方案", "成长规划 · 定制方案"); LoginCheck("全程跟踪辅导", "专家护航 · 全程陪伴") }
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Row(Modifier.weight(1f).semantics { role = Role.Checkbox; contentDescription = if (agreement) "已同意用户协议、隐私政策和儿童隐私政策" else "同意用户协议、隐私政策和儿童隐私政策" }.clickable { agreement = !agreement }) {
                            Checkbox(checked = agreement, onCheckedChange = { agreement = it })
                            Text(if (agreement) "已阅读并同意相关协议" else "请阅读并同意相关协议", color = if (agreement) Green else Color.Gray, fontSize = 8.sp)
                        }
                        TextButton(onClick = { legalDocument = "用户协议" }, contentPadding = PaddingValues(0.dp)) { Text("查看协议", color = Blue, fontSize = 9.sp) }
                    }
                }
            }
            Spacer(Modifier.height(18.dp))
            Image(painterResource(R.drawable.campus_footer), null, Modifier.fillMaxWidth().height(112.dp).scale(landscapeScale), contentScale = ContentScale.Fit)
            Spacer(Modifier.height(3.dp))
        }
    }
    legalDocument?.let { document ->
        AlertDialog(onDismissRequest = { legalDocument = null }, title = { Text(document) }, text = { Text("本页面为一期内测版展示。正式上线前将替换为经审核的完整文本，并说明账号、儿童健康数据、通知和第三方登录的处理规则。当前 Mock 数据不会上传到服务器。") }, confirmButton = { TextButton(onClick = { legalDocument = null }) { Text("完成") } })
    }
}

@Composable
fun RegisterScreen(
    onBack: () -> Unit,
    onRegistered: () -> Unit,
    loading: Boolean = false,
    serverError: String? = null,
    onClearError: () -> Unit = {}
) {
    var name by rememberSaveable { mutableStateOf("") }
    var phone by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var agreement by rememberSaveable { mutableStateOf(false) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var success by rememberSaveable { mutableStateOf(false) }
    var codeSent by rememberSaveable { mutableStateOf(false) }
    var codeCountdown by rememberSaveable { mutableIntStateOf(0) }
    LaunchedEffect(codeCountdown > 0) {
        while (codeCountdown > 0) {
            delay(1000)
            codeCountdown -= 1
        }
    }
    LaunchedEffect(serverError) {
        if (serverError != null) {
            success = false
            error = serverError
        }
    }
    AppScaffold(title = "注册账号", onBack = onBack) {
        if (success) {
            Column(Modifier.fillMaxWidth().padding(top = 80.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Filled.CheckCircle, null, tint = Green, modifier = Modifier.size(54.dp)); Text("注册成功", color = Navy, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp)); Text("账号已创建，请登录后选择使用角色。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp)); Button(onClick = { onClearError(); onRegistered() }, enabled = !loading, modifier = Modifier.padding(top = 20.dp)) { if (loading) CircularProgressIndicator(Modifier.size(17.dp), color = Color.White, strokeWidth = 2.dp) else Text("开始使用") }
            }
            return@AppScaffold
        }
        Text("创建向上少年账号", color = Navy, fontSize = 21.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp))
        Text("注册后可绑定家庭、接收学校通知并保存成长档案。", color = Color.Gray, fontSize = 11.sp, modifier = Modifier.padding(top = 5.dp, bottom = 14.dp))
        OutlinedTextField(value = name, onValueChange = { name = it; error = null }, label = { Text("姓名") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(value = phone, onValueChange = { phone = it; error = null }, label = { Text("手机号") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), singleLine = true, modifier = Modifier.fillMaxWidth().padding(top = 9.dp))
        Row(Modifier.fillMaxWidth().padding(top = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(value = code, onValueChange = { code = it; error = null }, label = { Text("短信验证码") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true, modifier = Modifier.weight(1f))
            TextButton(onClick = { if (phone.filter(Char::isDigit).length != 11) error = "请先填写 11 位手机号。" else { codeSent = true; code = "1234"; codeCountdown = 60 } }, enabled = codeCountdown == 0) { Text(if (codeCountdown > 0) "${codeCountdown}s" else if (codeSent) "重新获取" else "获取验证码", fontSize = 11.sp) }
        }
        OutlinedTextField(value = password, onValueChange = { password = it; error = null }, label = { Text("设置密码（至少 6 位）") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), singleLine = true, modifier = Modifier.fillMaxWidth().padding(top = 9.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp).semantics { role = Role.Checkbox; contentDescription = if (agreement) "已同意用户协议、隐私政策和儿童隐私政策" else "同意用户协议、隐私政策和儿童隐私政策" }.clickable { agreement = !agreement }) { Checkbox(checked = agreement, onCheckedChange = { agreement = it }); Text("我已阅读并同意用户协议、隐私政策和儿童隐私政策", color = Navy, fontSize = 10.sp) }
        error?.let { Text(it, color = Color.Red, fontSize = 10.sp) }
        Button(onClick = {
            when {
                name.isBlank() -> error = "请输入姓名。"
                phone.filter(Char::isDigit).length != 11 -> error = "请输入有效的 11 位手机号。"
                !codeSent -> error = "请先获取短信验证码。"
                code.length < 4 -> error = "请输入短信验证码。"
                password.length < 6 -> error = "密码至少需要 6 位。"
                !agreement -> error = "请先同意相关协议。"
                else -> success = true
            }
        }, enabled = agreement, modifier = Modifier.fillMaxWidth().padding(top = 12.dp).height(44.dp), shape = CircleShape) { Text("注册并登录", fontWeight = FontWeight.Bold) }
    }
}

@Composable
fun PasswordResetScreen(onBack: () -> Unit) {
    var phone by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var confirmation by rememberSaveable { mutableStateOf("") }
    var codeSent by rememberSaveable { mutableStateOf(false) }
    var codeCountdown by rememberSaveable { mutableIntStateOf(0) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var submitted by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(codeCountdown > 0) {
        while (codeCountdown > 0) {
            delay(1000)
            codeCountdown -= 1
        }
    }

    AppScaffold(title = "忘记密码", onBack = onBack) {
        if (submitted) {
            Column(
                Modifier.fillMaxWidth().padding(top = 80.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(Icons.Filled.CheckCircle, null, tint = Green, modifier = Modifier.size(56.dp))
                Text("密码已重置", color = Navy, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
                Text("请使用新密码重新登录。", color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
                Button(onClick = onBack, modifier = Modifier.padding(top = 20.dp), shape = CircleShape) { Text("返回登录") }
            }
            return@AppScaffold
        }

        Text("找回向上少年账号", color = Navy, fontSize = 21.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp))
        Text("验证手机号后设置新密码，验证码为 Mock 1234。", color = Color.Gray, fontSize = 11.sp, modifier = Modifier.padding(top = 5.dp, bottom = 14.dp))
        OutlinedTextField(
            value = phone,
            onValueChange = { phone = it; error = null },
            label = { Text("手机号") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Row(Modifier.fillMaxWidth().padding(top = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = code,
                onValueChange = { code = it; error = null },
                label = { Text("短信验证码") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
            TextButton(
                onClick = {
                    if (phone.filter(Char::isDigit).length != 11) error = "请输入有效的 11 位手机号。"
                    else { codeSent = true; code = "1234"; codeCountdown = 60; error = null }
                },
                enabled = codeCountdown == 0
            ) { Text(if (codeCountdown > 0) "${codeCountdown}s" else if (codeSent) "重新获取" else "获取验证码", fontSize = 11.sp) }
        }
        OutlinedTextField(
            value = password,
            onValueChange = { password = it; error = null },
            label = { Text("新密码（至少 6 位）") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(top = 9.dp)
        )
        OutlinedTextField(
            value = confirmation,
            onValueChange = { confirmation = it; error = null },
            label = { Text("再次输入新密码") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(top = 9.dp)
        )
        error?.let { Text(it, color = Color.Red, fontSize = 10.sp, modifier = Modifier.padding(top = 8.dp)) }
        Button(
            onClick = {
                when {
                    phone.filter(Char::isDigit).length != 11 -> error = "请输入有效的 11 位手机号。"
                    !codeSent -> error = "请先获取短信验证码。"
                    code.length < 4 -> error = "请输入短信验证码。"
                    password.length < 6 -> error = "新密码至少需要 6 位。"
                    password != confirmation -> error = "两次输入的密码不一致。"
                    else -> { error = null; submitted = true }
                }
            },
            modifier = Modifier.fillMaxWidth().padding(top = 14.dp).height(44.dp),
            shape = CircleShape
        ) { Text("确认重置密码", fontWeight = FontWeight.Bold) }
    }
}

@Composable private fun LoginButton(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, background: Color, foreground: Color, onClick: () -> Unit, outlined: Boolean = false) = Surface(
    onClick = onClick, modifier = Modifier.fillMaxWidth().height(39.dp).semantics { role = Role.Button; contentDescription = title }, color = background, shape = CircleShape, border = if (outlined) BorderStroke(1.dp, foreground) else null
) { Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = foreground, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(7.dp)); Text(title, color = foreground, fontSize = 13.sp, fontWeight = FontWeight.Bold) } }
@Composable private fun LoginCheck(title: String, note: String) = Row(verticalAlignment = Alignment.CenterVertically) { Surface(Modifier.size(18.dp), color = Green, shape = CircleShape) { Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.padding(4.dp)) }; Spacer(Modifier.width(8.dp)); Column { Text(title, color = Navy, fontSize = 10.sp, fontWeight = FontWeight.Bold); Text(note, color = Color.Gray, fontSize = 8.sp) } }

@Composable
fun RoleSelectScreen(onRole: (UserRole) -> Unit, onLogout: () -> Unit = {}) {
    val reduceMotion = LocalReduceMotion.current
    var appeared by remember { mutableStateOf(false) }
    val transition = rememberInfiniteTransition(label = "role-landscape")
    val landscapeScale by transition.animateFloat(1f, if (reduceMotion) 1f else 1.035f, infiniteRepeatable(tween(5400, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "role-landscape-scale")
    LaunchedEffect(Unit) { appeared = true }
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.White, Sky)))) {
        Column(Modifier.fillMaxSize().padding(horizontal = 19.dp).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.padding(top = 45.dp), verticalAlignment = Alignment.CenterVertically) { Text("请选择进入方式", color = Blue, fontSize = 18.sp, fontWeight = FontWeight.Bold); Spacer(Modifier.width(8.dp)); Icon(Icons.Filled.WbSunny, null, tint = Color(0xFFFFBD2E)) }
            Spacer(Modifier.height(20.dp))
            RoleCard(R.drawable.family_entrance, "家庭端", "家长查看孩子测评与成长建议", Blue, Color.White, appeared) { onRole(UserRole.Parent) }
            Spacer(Modifier.height(18.dp))
            RoleCard(R.drawable.school_entrance, "学校端", "教师与校长管理班级健康数据", Color.White, Blue, appeared) { onRole(UserRole.Teacher) }
            Spacer(Modifier.height(12.dp))
            RoleCard(R.drawable.school_entrance, "校长端", "查看学校总览、年级对比与风险学生", Navy, Color.White, appeared) { onRole(UserRole.Principal) }
            TextButton(onClick = onLogout) { Text("退出当前账号", color = Color.Gray, fontSize = 11.sp) }
            Spacer(Modifier.height(16.dp))
            Image(painterResource(R.drawable.campus_footer), null, Modifier.fillMaxWidth().height(132.dp).scale(landscapeScale), contentScale = ContentScale.Fit)
            Spacer(Modifier.height(4.dp))
        }
    }
}

@Composable private fun RoleCard(image: Int, title: String, detail: String, background: Color, foreground: Color, appeared: Boolean, onClick: () -> Unit) = Surface(
    onClick = onClick, modifier = Modifier.fillMaxWidth().height(112.dp).scale(if (appeared) 1f else .88f), color = background, shape = RoundedCornerShape(16.dp), border = if (background == Color.White) BorderStroke(1.dp, Color(0xFFFFBD2E)) else null
) { Row(Modifier.padding(17.dp), verticalAlignment = Alignment.CenterVertically) { Image(painterResource(image), null, Modifier.size(64.dp).clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Fit); Spacer(Modifier.width(17.dp)); Column(Modifier.weight(1f)) { Text(title, color = foreground, fontSize = 20.sp, fontWeight = FontWeight.Bold); Text(detail, color = if (background == Color.White) Color.Gray else Color.White.copy(.85f), fontSize = 9.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = if (background == Color.White) Color(0xFFFFB620) else Color.White) } }
